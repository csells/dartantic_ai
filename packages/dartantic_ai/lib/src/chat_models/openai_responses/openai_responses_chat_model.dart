import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../../agent/tool_constants.dart';
import '../../retry_http_client.dart';
import '../../shared/openai_utils.dart';
import 'openai_responses_chat_options.dart';
import 'openai_responses_event_mapper.dart';
import 'openai_responses_message_mapper.dart';
import 'openai_responses_server_side_tool_mapper.dart';
import 'openai_responses_server_side_tools.dart';

/// Chat model backed by the OpenAI Responses API.
class OpenAIResponsesChatModel
    extends ChatModel<OpenAIResponsesChatModelOptions> {
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

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses',
  );

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
    final registeredTools = tools; // Already filtered by the getter
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
    OpenAIResponsesChatModelOptions? options,
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
    final codeInterpreterConfig =
        options?.codeInterpreterConfig ?? defaultOptions.codeInterpreterConfig;
    final imageGenerationConfig =
        options?.imageGenerationConfig ?? defaultOptions.imageGenerationConfig;

    if ((codeInterpreterConfig?.shouldReuseContainer ?? false) && !store) {
      _logger.warning(
        'Code interpreter container reuse requested but store=false; '
        'previous_response_id will not be persisted.',
      );
    }

    final allTools = <openai.Tool>[
      ..._buildFunctionTools(),
      ...OpenAIResponsesServerSideToolMapper.buildServerSideTools(
        serverSideTools: serverSideTools,
        fileSearchConfig: fileSearchConfig,
        webSearchConfig: webSearchConfig,
        codeInterpreterConfig: codeInterpreterConfig,
        imageGenerationConfig: imageGenerationConfig,
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
      downloadContainerFile: downloadContainerFile,
    );

    try {
      await for (final event in responseStream.events) {
        _logger.fine('Received event: ${event.runtimeType}');
        final results = mapper.handle(event);
        await for (final result in results) {
          if (result.metadata.containsKey('thinking')) {
            _logger.fine(
              'Yielding result with thinking metadata: '
              '"${result.metadata['thinking']}"',
            );
          }
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

  /// Downloads a file from a code interpreter container.
  ///
  /// Files are generated by server-side code interpreter tool execution
  /// and need to be retrieved separately after the response completes.
  Future<ContainerFileData> downloadContainerFile(
    String containerId,
    String fileId,
  ) async {
    _logger.fine('Downloading container file: $fileId from $containerId');

    // NOTE: We cannot call retrieveContainerFile() to get the filename from
    // metadata.path because the OpenAI API returns "bytes": null for container
    // files, but openai_core 0.10.1's ContainerFile.fromJson() expects bytes to
    // always be a non-null integer (line 165), causing a type cast error.
    //
    // Bug report: https://github.com/meshagent/openai_core/issues/6
    //
    // For now, we use the fileId as the filename. Once openai_core is fixed to
    // handle nullable bytes, we can restore the metadata retrieval:
    //
    //   final metadata = await _client.retrieveContainerFile(containerId,
    //   fileId); final segments = metadata.path.split('/'); final rawFileName =
    //   segments.isNotEmpty ? segments.last : metadata.path; fileName =
    //   rawFileName.isEmpty ? fileId : rawFileName;

    final bytes = await _client.retrieveContainerFileContent(
      containerId,
      fileId,
    );

    return ContainerFileData(bytes: bytes, fileName: fileId);
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
      final parsed = openai.ReasoningOptions.fromJson(raw);
      resolvedEffort = parsed.effort;
      resolvedSummary = parsed.summary;
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
    return openai.ToolChoice.fromJson(raw);
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
}
