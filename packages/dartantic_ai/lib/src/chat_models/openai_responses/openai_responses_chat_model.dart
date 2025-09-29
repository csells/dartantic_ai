import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../../agent/tool_constants.dart';
import '../../retry_http_client.dart';
import '../../shared/openai_utils.dart';
import 'openai_responses_chat_options.dart';
import 'openai_responses_event_mapper.dart';
import 'openai_responses_message_mapper.dart';
import 'openai_responses_server_side_tools.dart';

/// Chat model backed by the OpenAI Responses API.
class OpenAIResponsesChatModel extends ChatModel<OpenAIResponsesChatOptions> {
  /// Creates a new OpenAI Responses chat model instance.
  OpenAIResponsesChatModel({
    required super.name,
    required super.defaultOptions,
    super.tools,
    super.temperature,
    this.baseUrl,
    this.apiKey,
    http.Client? httpClient,
  }) : _client = openai.OpenAIClient(
         apiKey: apiKey,
         // openai_core requires non-nullable baseUrl, use Responses endpoint
         // as default
         baseUrl: baseUrl?.toString() ?? 'https://api.openai.com/v1/responses',
         httpClient: RetryHttpClient(inner: httpClient ?? http.Client()),
       );

  static final Logger _logger =
      Logger('dartantic.chat.models.openai_responses');

  final openai.OpenAIClient _client;

  /// Base URL override for the OpenAI API.
  final Uri? baseUrl;

  /// API key used for authentication.
  final String? apiKey;

  @override
  List<Tool>? get tools {
    // Filter out return_result from the tools list since we handle
    // outputSchema natively
    final baseTools = super.tools;
    if (baseTools == null) return null;
    return baseTools
        .where((tool) => tool.name != kReturnResultToolName)
        .toList();
  }

  List<openai.Tool> _buildFunctionTools() {
    final registeredTools = tools;  // Already filtered by the getter
    if (registeredTools == null || registeredTools.isEmpty) {
      return const [];
    }

    final mapped = registeredTools
        .map(
          (tool) => openai.FunctionTool(
            name: tool.name,
            description: tool.description,
            parameters: Map<String, dynamic>.from(
              tool.inputSchema.schemaMap ?? {},
            ),
          ),
        )
        .toList(growable: false);
    return mapped;
  }

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    OpenAIResponsesChatOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    final store = options?.store ?? defaultOptions.store ?? true;

    final history = OpenAIResponsesMessageMapper.mapHistory(
      messages,
      store: store,
      imageDetail:
          options?.imageDetail ??
          defaultOptions.imageDetail ??
          openai.ImageDetail.auto,
    );

    if (!history.hasInput && history.previousResponseId == null) {
      throw ArgumentError('No new input provided to OpenAI Responses request');
    }

    final temperatureOverride =
        options?.temperature ?? defaultOptions.temperature;
    final topP = options?.topP ?? defaultOptions.topP;
    final maxOutputTokens =
        options?.maxOutputTokens ?? defaultOptions.maxOutputTokens;
    final parallelToolCalls =
        options?.parallelToolCalls ?? defaultOptions.parallelToolCalls;
    final include = options?.include ?? defaultOptions.include;
    final metadata = _mergeMetadata(defaultOptions.metadata, options?.metadata);
    final reasoning = _toReasoningOptions(
      raw: options?.reasoning ?? defaultOptions.reasoning,
      effort: options?.reasoningEffort ?? defaultOptions.reasoningEffort,
      summary: options?.reasoningSummary ?? defaultOptions.reasoningSummary,
    );
    final toolChoice = _toToolChoice(
      options?.toolChoice ?? defaultOptions.toolChoice,
    );
    final truncation = _toTruncation(
      options?.truncationStrategy ?? defaultOptions.truncationStrategy,
    );
    final textFormat = _resolveTextFormat(
      outputSchema,
      options?.responseFormat ?? defaultOptions.responseFormat,
    );

    final requestServerTools = options?.serverSideTools;
    final Set<OpenAIServerSideTool> serverSideTools;
    if (requestServerTools != null) {
      serverSideTools = {...requestServerTools};
    } else if (defaultOptions.serverSideTools != null) {
      serverSideTools = {...defaultOptions.serverSideTools!};
    } else {
      serverSideTools = <OpenAIServerSideTool>{};
    }

    final fileSearchConfig =
        options?.fileSearchConfig ?? defaultOptions.fileSearchConfig;
    final webSearchConfig =
        options?.webSearchConfig ?? defaultOptions.webSearchConfig;
    final computerUseConfig =
        options?.computerUseConfig ?? defaultOptions.computerUseConfig;
    final codeInterpreterConfig =
        options?.codeInterpreterConfig ?? defaultOptions.codeInterpreterConfig;

    if ((codeInterpreterConfig?.shouldReuseContainer ?? false) && !store) {
      _logger.warning(
        'Code interpreter container reuse requested but store=false; '
        'previous_response_id will not be persisted.',
      );
    }

    final allTools = <openai.Tool>[
      ..._buildFunctionTools(),
      ...OpenAIResponsesChatModel.buildServerSideTools(
        serverSideTools: serverSideTools,
        fileSearchConfig: fileSearchConfig,
        webSearchConfig: webSearchConfig,
        computerUseConfig: computerUseConfig,
        codeInterpreterConfig: codeInterpreterConfig,
      ),
    ];

    final responseStream = await _client.streamResponse(
      model: openai.ChatModel(name),
      input: history.input,
      instructions: history.instructions,
      previousResponseId: history.previousResponseId,
      store: store,
      temperature: temperatureOverride ?? temperature,
      topP: topP,
      maxOutputTokens: maxOutputTokens,
      reasoning: reasoning,
      text: textFormat,
      toolChoice: toolChoice,
      tools: allTools.isEmpty ? null : allTools,
      parallelToolCalls: parallelToolCalls,
      metadata: metadata,
      include: include,
      truncation: truncation,
      user: options?.user ?? defaultOptions.user,
    );

    final mapper = OpenAIResponsesEventMapper(
      modelName: name,
      storeSession: store,
      history: history,
    );

    try {
      await for (final event in responseStream.events) {
        _logger.fine('Received event: ${event.runtimeType}');
        final results = mapper.handle(event);
        for (final result in results) {
          yield result;
        }
      }
    } on Object catch (error, stackTrace) {
      _logger.severe(
        'OpenAI Responses stream error: $error',
        error,
        stackTrace,
      );
      rethrow;
    }
  }

  @override
  void dispose() => _client.close();

  /// Converts dartantic tool preferences into OpenAI Responses tool payloads.
  ///
  /// Exposed for testing so unit tests can validate the mapping without
  /// constructing a full streaming session.
  @visibleForTesting
  static List<openai.Tool> buildServerSideTools({
    required Set<OpenAIServerSideTool> serverSideTools,
    FileSearchConfig? fileSearchConfig,
    WebSearchConfig? webSearchConfig,
    ComputerUseConfig? computerUseConfig,
    CodeInterpreterConfig? codeInterpreterConfig,
  }) {
    if (serverSideTools.isEmpty) return const [];

    final tools = <openai.Tool>[];

    for (final tool in serverSideTools) {
      switch (tool) {
        case OpenAIServerSideTool.webSearch:
          final config = webSearchConfig;
          tools.add(
            openai.WebSearchPreviewTool(
              searchContextSize: _mapSearchContextSize(config?.contextSize),
              userLocation: _mapUserLocation(config?.location),
            ),
          );
          continue;
        case OpenAIServerSideTool.fileSearch:
          final config = fileSearchConfig;
          if (config == null) {
            _logger.warning(
              'File search tool requested but no FileSearchConfig provided; '
              'skipping.',
            );
            continue;
          }
          if (!config.hasVectorStores) {
            _logger.warning(
              'File search tool requested but no vectorStoreIds provided; '
              'skipping.',
            );
            continue;
          }

          openai.FileSearchFilter? parsedFilter;
          if (config.filters != null && config.filters!.isNotEmpty) {
            try {
              parsedFilter = openai.FileSearchFilter.fromJson(
                Map<String, dynamic>.from(config.filters!),
              );
            } on Object catch (error, stackTrace) {
              _logger.warning(
                'Failed to parse file search filters: $error',
                error,
                stackTrace,
              );
            }
          }

          openai.RankingOptions? rankingOptions;
          if (config.ranker != null || config.scoreThreshold != null) {
            rankingOptions = openai.RankingOptions(
              ranker: config.ranker,
              scoreThreshold: config.scoreThreshold,
            );
          }

          tools.add(
            openai.FileSearchTool(
              vectorStoreIds: config.vectorStoreIds,
              filters: parsedFilter == null ? null : [parsedFilter],
              maxNumResults: config.maxResults,
              rankingOptions: rankingOptions,
            ),
          );
          continue;
        case OpenAIServerSideTool.computerUse:
          final config = computerUseConfig ?? const ComputerUseConfig();
          tools.add(
            openai.ComputerUsePreviewTool(
              displayHeight: config.displayHeight,
              displayWidth: config.displayWidth,
              environment: config.environment,
            ),
          );
          continue;
        case OpenAIServerSideTool.imageGeneration:
          tools.add(const openai.ImageGenerationTool());
          continue;
        case OpenAIServerSideTool.codeInterpreter:
          final config = codeInterpreterConfig;
          openai.CodeInterpreterContainer container;
          if (config != null && config.shouldReuseContainer) {
            container = openai.CodeInterpreterContainerId(config.containerId!);
          } else {
            container = openai.CodeInterpreterContainerAuto(
              fileIds: config?.fileIds,
            );
          }
          tools.add(openai.CodeInterpreterTool(container: container));
          continue;
      }
    }

    return tools;
  }

  static Map<String, dynamic>? _mergeMetadata(
    Map<String, dynamic>? base,
    Map<String, dynamic>? override,
  ) {
    if (base == null && override == null) return null;
    return {if (base != null) ...base, if (override != null) ...override};
  }

  static openai.ReasoningOptions? _toReasoningOptions({
    Map<String, dynamic>? raw,
    OpenAIReasoningEffort? effort,
    OpenAIReasoningSummary? summary,
  }) {
    openai.ReasoningEffort? resolvedEffort;
    openai.ReasoningDetail? resolvedSummary;

    if (raw != null && raw.isNotEmpty) {
      try {
        final parsed = openai.ReasoningOptions.fromJson(raw);
        resolvedEffort = parsed.effort;
        resolvedSummary = parsed.summary;
      } on Object catch (error, stackTrace) {
        _logger.warning(
          'Failed to parse reasoning options map: $error',
          error,
          stackTrace,
        );
      }
    }

    if (effort != null) {
      resolvedEffort = switch (effort) {
        OpenAIReasoningEffort.low => openai.ReasoningEffort.low,
        OpenAIReasoningEffort.medium => openai.ReasoningEffort.medium,
        OpenAIReasoningEffort.high => openai.ReasoningEffort.high,
      };
    }

    if (summary != null) {
      resolvedSummary = switch (summary) {
        OpenAIReasoningSummary.detailed => openai.ReasoningDetail.detailed,
        OpenAIReasoningSummary.concise => openai.ReasoningDetail.concise,
        OpenAIReasoningSummary.auto => openai.ReasoningDetail.auto,
        OpenAIReasoningSummary.none => null,
      };
    }

    if (resolvedEffort == null && resolvedSummary == null) {
      return null;
    }

    return openai.ReasoningOptions(
      effort: resolvedEffort,
      summary: resolvedSummary,
    );
  }

  static openai.ToolChoice? _toToolChoice(dynamic raw) {
    if (raw == null) return null;
    try {
      return openai.ToolChoice.fromJson(raw);
    } on Object catch (_) {
      return openai.ToolChoiceOther(raw);
    }
  }

  static openai.Truncation? _toTruncation(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return null;
    final type = raw['type'];
    if (type is String) {
      switch (type) {
        case 'auto':
          return openai.Truncation.auto;
        case 'disabled':
          return openai.Truncation.disabled;
      }
    }
    return null;
  }

  static openai.TextFormat? _resolveTextFormat(
    JsonSchema? outputSchema,
    Map<String, dynamic>? responseFormat,
  ) {
    if (outputSchema != null) {
      final raw = outputSchema.schemaMap ?? const <String, dynamic>{};
      final schema = OpenAIUtils.prepareSchemaForOpenAI(
        Map<String, dynamic>.from(raw),
      );
      return openai.TextFormatJsonSchema(
        name: 'dartantic_output',
        schema: schema,
        description: schema['description'] as String?,
        strict: true,
      );
    }
    if (responseFormat == null) return null;
    return openai.TextFormat.fromJson(responseFormat);
  }

  static openai.SearchContextSize? _mapSearchContextSize(
    WebSearchContextSize? size,
  ) {
    switch (size) {
      case WebSearchContextSize.low:
        return openai.SearchContextSize.low;
      case WebSearchContextSize.medium:
        return openai.SearchContextSize.medium;
      case WebSearchContextSize.high:
        return openai.SearchContextSize.high;
      case WebSearchContextSize.other:
        return openai.SearchContextSize.other;
      case null:
        return null;
    }
  }

  static openai.UserLocation? _mapUserLocation(WebSearchLocation? location) {
    if (location == null || location.isEmpty) return null;
    return openai.UserLocation(
      city: location.city,
      region: location.region,
      country: location.country,
      timezone: location.timezone,
    );
  }
}
