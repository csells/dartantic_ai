import 'dart:async';
import 'dart:convert';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as a;
// ignore: implementation_imports
import 'package:anthropic_sdk_dart/src/generated/client.dart' as ag;
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../../media_gen_models/anthropic/anthropic_files_client.dart';
import '../../media_gen_models/anthropic/anthropic_tool_deliverable_tracker.dart';
import 'anthropic_chat_options.dart';
import 'anthropic_message_mappers.dart';
import 'anthropic_server_side_tool_types.dart';
import 'anthropic_server_side_tools.dart';

/// Wrapper around [Anthropic Messages
/// API](https://docs.anthropic.com/en/api/messages) (aka Claude API).
class AnthropicChatModel extends ChatModel<AnthropicChatOptions> {
  /// Creates a [AnthropicChatModel] instance.
  ///
  /// When [autoDownloadFiles] is true (the default when code execution is
  /// enabled), files created by code execution are automatically downloaded
  /// from the Anthropic Files API and added as DataParts to messages.
  AnthropicChatModel({
    required super.name,
    required String apiKey,
    Uri? baseUrl,
    super.tools,
    super.temperature,
    bool enableThinking = false,
    http.Client? client,
    Map<String, String>? headers,
    AnthropicChatOptions? defaultOptions,
    List<String> betaFeatures = const [],
    bool? autoDownloadFiles,
  }) : _enableThinking = enableThinking,
       _client = _AnthropicStreamingClient(
         apiKey: apiKey,
         baseUrl: baseUrl?.toString(),
         client: client,
         headers: headers,
         betaFeatures: betaFeatures,
       ),
       _filesClient = (autoDownloadFiles ?? _hasCodeExecution(defaultOptions))
           ? AnthropicFilesClient(
               apiKey: apiKey,
               baseUrl: baseUrl,
               betaFeatures: betaFeatures,
             )
           : null,
       super(defaultOptions: defaultOptions ?? const AnthropicChatOptions()) {
    _logger.info(
      'Creating Anthropic model: $name with '
      '${tools?.length ?? 0} tools, temp: $temperature, '
      'thinking: $enableThinking, autoDownloadFiles: ${_filesClient != null}',
    );
  }

  /// Logger for Anthropic chat model operations.
  static final Logger _logger = Logger('dartantic.chat.models.anthropic');

  final _AnthropicStreamingClient _client;
  final bool _enableThinking;
  final AnthropicFilesClient? _filesClient;

  /// Checks if code execution is enabled in the options.
  static bool _hasCodeExecution(AnthropicChatOptions? options) {
    if (options == null) return false;

    // Check serverSideTools enum set
    final serverSideTools = options.serverSideTools;
    if (serverSideTools != null &&
        serverSideTools.contains(AnthropicServerSideTool.codeInterpreter)) {
      return true;
    }

    // Check manual serverTools configs
    final serverTools = options.serverTools;
    if (serverTools != null) {
      for (final tool in serverTools) {
        if (tool.name == 'code_execution' ||
            tool.type.startsWith('code_execution')) {
          return true;
        }
      }
    }

    return false;
  }

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    AnthropicChatOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    _logger.info(
      'Starting Anthropic chat stream with '
      '${messages.length} messages for model: $name',
    );

    final transformer = MessageStreamEventTransformer();
    final request = createMessageRequest(
      messages,
      modelName: name,
      enableThinking: _enableThinking,
      tools: tools,
      temperature: temperature,
      options: options,
      defaultOptions: defaultOptions,
      outputSchema: outputSchema,
    );

    // Create tracker for file downloads if files client is available
    final tracker = _filesClient != null
        ? AnthropicToolDeliverableTracker(
            _filesClient,
            targetMimeTypes: const {'*/*'},
          )
        : null;

    var chunkCount = 0;
    ChatResult<ChatMessage>? lastResult;

    // TODO(https://github.com/davidmigloz/langchain_dart/issues/811): revert to
    // `_client.createMessageStream(...).transform(transformer)` once
    // `anthropic_sdk_dart` understands the `signature_delta` union variant.
    await for (final result in _createMessageEventStream(
      request,
      transformer,
    ).transform(transformer)) {
      chunkCount++;
      _logger.fine('Received Anthropic stream chunk $chunkCount');

      // Process metadata for file deliverables during streaming
      if (tracker != null && result.metadata.isNotEmpty) {
        final emission = await tracker.handleMetadata(result.metadata);
        if (emission.assets.isNotEmpty) {
          // Yield assets discovered from metadata immediately
          yield ChatResult<ChatMessage>(
            id: result.id,
            output: ChatMessage(
              role: ChatMessageRole.model,
              parts: emission.assets,
            ),
            messages: [
              ChatMessage(role: ChatMessageRole.model, parts: emission.assets),
            ],
            finishReason: FinishReason.unspecified,
            metadata: const {},
            usage: null,
          );
        }
      }

      lastResult = result;
      yield ChatResult<ChatMessage>(
        id: result.id,
        output: result.output,
        messages: result.messages,
        finishReason: result.finishReason,
        metadata: result.metadata,
        thinking: result.thinking,
        usage: result.usage,
      );
    }

    // After streaming completes, collect any remaining files from the API
    if (tracker != null && lastResult != null) {
      final remoteFiles = await tracker.collectRecentFiles();
      if (remoteFiles.isNotEmpty) {
        _logger.fine(
          'Downloaded ${remoteFiles.length} files from Anthropic Files API',
        );
        yield ChatResult<ChatMessage>(
          id: lastResult.id,
          output: ChatMessage(role: ChatMessageRole.model, parts: remoteFiles),
          messages: [
            ChatMessage(role: ChatMessageRole.model, parts: remoteFiles),
          ],
          finishReason: FinishReason.unspecified,
          metadata: {'auto_downloaded_files': remoteFiles.length},
          usage: null,
        );
      }
    }
  }

  @override
  void dispose() {
    _client.endSession();
    _filesClient?.close();
  }

  Stream<a.MessageStreamEvent> _createMessageEventStream(
    a.CreateMessageRequest request,
    MessageStreamEventTransformer transformer,
  ) async* {
    final requestMap = request.toJson();
    requestMap['stream'] = true;
    _stripServerToolInputSchemas(requestMap);

    final lines = _client.rawMessageStream(requestMap);

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;

      final map = json.decode(payload) as Map<String, dynamic>;
      _registerRawToolPayload(map, transformer);
      _normalizeServerToolEvent(map);
      final type = map['type'];

      if (type == 'content_block_delta') {
        final delta = map['delta'];
        if (delta is Map && delta['type'] == 'citations_delta') {
          _logger.fine('Skipping unsupported citations_delta event');
          continue;
        }
      }

      if (type == 'signature_delta' ||
          (map['delta'] is Map &&
              (map['delta'] as Map)['type'] == 'signature_delta')) {
        final signature =
            map['signature'] as String? ??
            (map['delta'] as Map?)?['signature'] as String?;
        if (signature != null && signature.isNotEmpty) {
          _logger.fine('Captured signature delta for thinking block');
          transformer.recordSignatureDelta(signature);
        } else {
          _logger.warning(
            'Received signature_delta event without signature: $map',
          );
        }
        continue;
      }

      yield a.MessageStreamEvent.fromJson(map);
    }
  }

  void _stripServerToolInputSchemas(Map<String, dynamic> request) {
    final tools = request['tools'];
    if (tools is! List) return;

    for (final entry in tools) {
      if (entry is! Map<String, dynamic>) continue;
      final type = entry['type'] as String?;
      final name = entry['name'] as String?;
      if (_shouldStripInputSchema(type, name)) {
        entry.remove('input_schema');
      }
    }
  }

  bool _shouldStripInputSchema(String? type, String? name) {
    const typesNeedingRemoval = {
      'code_execution_20250825',
      'web_search_20250305',
      'web_fetch_20250910',
    };
    const namesNeedingRemoval = {'code_execution', 'web_search', 'web_fetch'};
    return (type != null && typesNeedingRemoval.contains(type)) ||
        (name != null && namesNeedingRemoval.contains(name));
  }

  void _registerRawToolPayload(
    Map<String, dynamic> event,
    MessageStreamEventTransformer transformer,
  ) {
    if (event['type'] != 'content_block_start') return;

    final contentBlock = event['content_block'];
    if (contentBlock is! Map<String, dynamic>) return;

    final toolUseId = contentBlock['tool_use_id'];
    if (toolUseId is! String || toolUseId.isEmpty) return;

    final blockType = contentBlock['type'];
    if (blockType == AnthropicServerToolTypes.serverToolUse) {
      final input = contentBlock['input'];
      if (input is Map<String, Object?>) {
        transformer.registerRawToolContent(toolUseId, input);
      }
      return;
    }

    if (blockType is String &&
        blockType.endsWith(AnthropicServerToolTypes.toolResultSuffix)) {
      final content = contentBlock['content'];
      if (content is Map<String, Object?>) {
        transformer.registerRawToolContent(toolUseId, content);
      }
      // Replace content with empty string to satisfy JSON decoder expectations.
      contentBlock['content'] = '';
    }
  }

  void _normalizeServerToolEvent(Map<String, dynamic> event) {
    if (event['type'] == 'content_block_start') {
      final contentBlock = event['content_block'];
      if (contentBlock is Map<String, dynamic>) {
        final blockType = contentBlock['type'];
        if (blockType == AnthropicServerToolTypes.serverToolUse) {
          contentBlock['type'] = AnthropicServerToolTypes.toolUse;
        } else if (blockType is String &&
            blockType.endsWith(AnthropicServerToolTypes.toolResultSuffix)) {
          contentBlock['type'] = AnthropicServerToolTypes.toolResult;
        }
      }
    }

    if (event['type'] == 'content_block_stop') {
      final contentBlock = event['content_block'];
      if (contentBlock is Map<String, dynamic>) {
        final blockType = contentBlock['type'];
        if (blockType == AnthropicServerToolTypes.serverToolUse) {
          contentBlock['type'] = AnthropicServerToolTypes.toolUse;
        } else if (blockType is String &&
            blockType.endsWith(AnthropicServerToolTypes.toolResultSuffix)) {
          contentBlock['type'] = AnthropicServerToolTypes.toolResult;
        }
      }
    }
  }
}

class _AnthropicStreamingClient extends a.AnthropicClient {
  _AnthropicStreamingClient({
    required super.apiKey,
    super.baseUrl,
    super.client,
    Map<String, String>? headers,
    List<String> betaFeatures = const [],
  }) : super(
         headers: {
           'anthropic-beta': _buildBetaHeader(betaFeatures),
           ...?headers,
         },
       );

  static const List<String> _defaultBetaFeatures = <String>[
    'message-batches-2024-09-24',
    'prompt-caching-2024-07-31',
    'computer-use-2024-10-22',
  ];

  static String _buildBetaHeader(List<String> extras) {
    final features = <String>{..._defaultBetaFeatures, ...extras};
    return features.join(',');
  }

  Stream<String> rawMessageStream(Object request) async* {
    final response = await makeRequestStream(
      baseUrl: baseUrl ?? 'https://api.anthropic.com/v1',
      path: '/messages',
      method: ag.HttpMethod.post,
      requestType: 'application/json',
      responseType: 'application/json',
      body: request,
      headerParams: {if (apiKey.isNotEmpty) 'x-api-key': apiKey},
    );

    yield* response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
  }
}
