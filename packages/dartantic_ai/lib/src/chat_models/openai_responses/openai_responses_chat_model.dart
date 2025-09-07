import 'dart:async';
import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../../agent/tool_constants.dart';
import '../../chat_models/chat_utils.dart';
import '../../retry_http_client.dart';
import '../openai_chat/openai_message_mappers.dart'
    show createCompleteMessageWithTools;
import '../openai_chat/openai_message_mappers_helpers.dart'
    show StreamingToolCall;
import 'openai_responses_cache_config.dart';
import 'openai_responses_chat_options.dart';
import 'openai_responses_message_mappers.dart';

/// Chat model backed by the OpenAI Responses API (streaming).
///
/// Supports full tool calling functionality including proper argument parsing.
/// Note: This API follows a different flow than Chat Completions - tool results
/// are not sent back to the API as the model handles tool calling in a single
/// round-trip.
class OpenAIResponsesChatModel extends ChatModel<OpenAIResponsesChatOptions> {
  /// Creates a [OpenAIResponsesChatModel] instance.
  OpenAIResponsesChatModel({
    required super.name,
    String? apiKey,
    List<Tool>? tools,
    super.temperature,
    OpenAIResponsesChatOptions? defaultOptions,
    Uri? baseUrl,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParams,
    http.Client? client,
  }) : _apiKey = apiKey,
       _baseUrl = baseUrl,
       _headers = headers,
       _queryParams = queryParams,
       _client = client != null
           ? RetryHttpClient(inner: client)
           : RetryHttpClient(inner: http.Client()),
       super(
         defaultOptions: defaultOptions ?? const OpenAIResponsesChatOptions(),
         // Filter out return_result tool as OpenAI Responses has native typed
         // output support
         tools: () {
           if (tools == null) return null;
           final filtered = tools
               .where((t) => t.name != kReturnResultToolName)
               .toList();
           return filtered.isEmpty ? null : filtered;
         }(),
       );

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses',
  );

  final String? _apiKey;
  final Uri? _baseUrl;
  final Map<String, String>? _headers;
  final Map<String, dynamic>? _queryParams;
  final http.Client _client;

  static final Uri _defaultBaseUrl = Uri.parse('https://api.openai.com/v1');

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    OpenAIResponsesChatOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    _logger.info(
      'Starting OpenAI Responses stream with ${messages.length} messages for '
      'model: $name',
    );

    final resolvedBaseUrl = _baseUrl ?? _defaultBaseUrl;
    final url = appendPath(resolvedBaseUrl, 'responses');

    // Extract response ID for tool result linking and explicit container reuse
    String? previousResponseId;
    final hasAnyToolResults = messages.any(
      (m) => m.parts.any((p) => p is ToolPart && p.kind == ToolPartKind.result),
    );
    
    // Check if container reuse is explicitly requested
    final codeInterpreterConfig = options?.codeInterpreterConfig ?? 
                                   defaultOptions.codeInterpreterConfig;
    final shouldReuseContainer = 
        codeInterpreterConfig?.shouldReuseContainer ?? false;
    final requestedContainerId = codeInterpreterConfig?.containerId;
    
    // Only look for previous_response_id if:
    // 1. We have tool results that need linking, OR
    // 2. Container reuse is explicitly requested
    //
    // NOTE: Container reuse via container_id alone does NOT work with the
    // OpenAI Responses API. Testing confirmed that passing container_id 
    // directly (e.g., "container": "cntr_...") is accepted by the API but 
    // does NOT preserve container state. Only previous_response_id properly 
    // maintains container state across requests.
    if (hasAnyToolResults || shouldReuseContainer) {
      for (var i = messages.length - 1; i >= 0; i--) {
        final msg = messages[i];
        if (msg.role == ChatMessageRole.model) {
          // For tool results, we need a message with tool calls
          if (hasAnyToolResults &&
              !msg.parts.any(
                (p) => p is ToolPart && p.kind == ToolPartKind.call,
              )) {
            continue;
          }
          
          // Try to get response_id from metadata
          final msgResponseId = msg.metadata['response_id'] as String?;
          final msgContainerId = msg.metadata['container_id'] as String?;
          
          // For container reuse, check if this message has the requested 
          // container
          if (shouldReuseContainer && requestedContainerId != null) {
            if (msgContainerId == requestedContainerId && 
                msgResponseId != null) {
              previousResponseId = msgResponseId;
              _logger.info(
                'Found response ID for container reuse: $previousResponseId '
                '(container: $requestedContainerId)',
              );
              break;
            }
            // Continue looking for matching container
            continue;
          }
          
          // For tool results, just use the response_id if available
          if (hasAnyToolResults && msgResponseId != null) {
            previousResponseId = msgResponseId;
            _logger.info(
              'Found previous response ID for tool result linking: '
              '$previousResponseId',
            );
            break;
          }
        }
      }
      
      // Warn if container reuse was requested but no matching response found
      if (shouldReuseContainer && previousResponseId == null) {
        _logger.warning(
          'Container reuse requested for $requestedContainerId but no matching '
          'response_id found in history',
        );
      }
    }

    final payload = buildResponsesRequest(
      messages,
      modelName: name,
      tools: tools,
      temperature: temperature,
      defaultOptions: defaultOptions,
      options: options,
      outputSchema: outputSchema,
      previousResponseId: previousResponseId,
    );

    // Build URL with optional query params before creating the request
    final effectiveUrl = (_queryParams != null && _queryParams.isNotEmpty)
        ? url.replace(
            queryParameters: {
              ...url.queryParameters,
              ..._queryParams.map((k, v) => MapEntry(k, v.toString())),
            },
          )
        : url;

    final request = http.Request('POST', effectiveUrl);
    // Apply cache headers from options if enabled
    final cacheCfg = options?.cacheConfig ?? defaultOptions.cacheConfig;
    final extraHeaders = <String, String>{};
    if (cacheCfg != null && cacheCfg.enabled) {
      if (cacheCfg.sessionId != null && cacheCfg.sessionId!.isNotEmpty) {
        extraHeaders['X-OpenAI-Session-ID'] = cacheCfg.sessionId!;
      }
      if (cacheCfg.cacheControl != null) {
        extraHeaders['Cache-Control'] = cacheCfg.cacheControl!.headerValue;
      }
      if (cacheCfg.ttlSeconds > 0) {
        extraHeaders['X-OpenAI-Cache-TTL'] = cacheCfg.ttlSeconds.toString();
      }
    }

    request.headers.addAll({
      if (_apiKey != null && _apiKey.isNotEmpty)
        'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      ...extraHeaders,
      ...?_headers,
    });

    request.body = json.encode(payload);

    final accumulatedToolCalls = <StreamingToolCall>[];
    final accumulatedTextBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final reasoningDeltaBuffer = StringBuffer();
    // Media accumulation for providers that stream images/audio
    final mediaBase64 = <String, StringBuffer>{};
    final mediaMime = <String, String>{};
    var chunkCount = 0;

    var lastResult = ChatResult<ChatMessage>(
      output: const ChatMessage(role: ChatMessageRole.model, parts: []),
      finishReason: FinishReason.unspecified,
      metadata: const {},
      usage: const LanguageModelUsage(),
    );

    // Track response ID for linking tool result requests
    String? responseId;
    // Track container ID for code_interpreter sessions
    String? containerId;

    http.StreamedResponse? streamedResponse;
    try {
      streamedResponse = await _client.send(request);
      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        throw Exception(
          'OpenAI Responses error: HTTP ${streamedResponse.statusCode}: $body',
        );
      }

      // Cache metrics from response headers
      bool? cacheHit;
      if (cacheCfg != null && cacheCfg.enabled && cacheCfg.trackMetrics) {
        final hdr = streamedResponse.headers['x-openai-cache-hit'];
        if (hdr != null) {
          cacheHit = hdr.toLowerCase() == 'true' || hdr == '1';
          _logger.info('OpenAI Responses cache hit: $cacheHit');
          // attach to current lastResult metadata
          lastResult = ChatResult<ChatMessage>(
            output: lastResult.output,
            messages: lastResult.messages,
            finishReason: lastResult.finishReason,
            metadata: {
              ...lastResult.metadata,
              'cache': {
                'hit': cacheHit,
                if (cacheCfg.sessionId != null) 'session': cacheCfg.sessionId,
                if (cacheCfg.ttlSeconds > 0) 'ttl': cacheCfg.ttlSeconds,
              },
            },
            usage: lastResult.usage,
          );
          yield lastResult;
        }
      }

      String? currentEvent;
      final dataBuffer = StringBuffer();

      final lines = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (line.startsWith('event:')) {
          // Log event line for debugging SSE sequencing
          final evName = line.substring('event:'.length).trim();
          _logger.info('SSE event: $evName');
          // Process any pending event before switching
          if (currentEvent != null) {
            final dataStr = dataBuffer.toString();
            dataBuffer.clear();

            if (dataStr.trim().isEmpty) {
              // Nothing buffered for this event; move on
              currentEvent = null;
              continue;
            }

            Map<String, dynamic> data;
            try {
              data = json.decode(dataStr) as Map<String, dynamic>;

              // Capture response ID from response.created event
              _logger.info(
                'Processing event: $currentEvent, responseId: $responseId',
              );
              if (responseId == null &&
                  currentEvent == 'response.created' &&
                  data.containsKey('response')) {
                final respData = data['response'];
                if (respData is Map<String, dynamic> &&
                    respData.containsKey('id')) {
                  responseId = respData['id']?.toString();
                  _logger.info(
                    'Captured response ID from response.created: $responseId',
                  );

                  // Update lastResult with response ID in metadata and yield it
                  final metadata = Map<String, dynamic>.from(
                    lastResult.metadata,
                  );
                  if (responseId != null) {
                    metadata['response_id'] = responseId;
                  }
                  lastResult = ChatResult<ChatMessage>(
                    output: lastResult.output,
                    messages: lastResult.messages,
                    finishReason: lastResult.finishReason,
                    metadata: metadata,
                    usage: lastResult.usage,
                  );
                  yield lastResult;
                }
              }
            } on Object {
              // If we somehow received an incomplete JSON chunk, skip
              // gracefully
              currentEvent = null;
              continue;
            }

            // Handle previous event
            if (currentEvent == 'response.output_text.delta') {
              // If there is pending reasoning delta, emit it BEFORE text
              if (reasoningDeltaBuffer.isNotEmpty) {
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {'thinking': reasoningDeltaBuffer.toString()},
                  usage: lastResult.usage,
                );
                yield lastResult;
                reasoningDeltaBuffer.clear();
              }
              final delta = (data['delta'] ?? data['text'] ?? '').toString();
              if (delta.isNotEmpty) {
                chunkCount++;
                accumulatedTextBuffer.write(delta);

                // Include response ID and container ID in metadata if available
                final streamingMetadata = <String, dynamic>{};
                if (reasoningDeltaBuffer.isNotEmpty) {
                  streamingMetadata['thinking'] = reasoningDeltaBuffer
                      .toString();
                }
                if (responseId != null) {
                  streamingMetadata['response_id'] = responseId;
                }
                if (containerId != null) {
                  streamingMetadata['container_id'] = containerId;
                }
                
                final message = ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [TextPart(delta)],
                  metadata: streamingMetadata,
                );

                lastResult = ChatResult<ChatMessage>(
                  output: message,
                  messages: [message],
                  finishReason: FinishReason.unspecified,
                  metadata: streamingMetadata,
                  usage: lastResult.usage,
                );
                yield lastResult;
                reasoningDeltaBuffer.clear();
              }
            } else if (currentEvent == 'response.output_item.added') {
              final item = data['item'] as Map<String, dynamic>?;
              if (item?['type'] == 'function_call') {
                final callId = (item?['call_id'] ?? '').toString();
                final name = (item?['name'] ?? '').toString();
                final itemId = (item?['id'] ?? '').toString();

                if (callId.isNotEmpty && name.isNotEmpty && itemId.isNotEmpty) {
                  _logger.info(
                    'Tool call added: '
                    'callId=$callId, name=$name, itemId=$itemId',
                  );
                  // Use item_id as the key for matching arguments later
                  accumulatedToolCalls.add(
                    StreamingToolCall(
                      // Use callId as primary ID to match function_call_output
                      id: callId,
                      name: name,
                      itemId: itemId,
                    ),
                  );
                }
              } else if (item != null &&
                  (item['type'] == 'image' ||
                      item['type'] == 'output_image' ||
                      item['type'] == 'audio' ||
                      item['type'] == 'output_audio')) {
                final itemId = (item['id'] ?? '').toString();
                final mimeType = (item['mime_type'] ?? '').toString();
                if (itemId.isNotEmpty) {
                  _logger.info(
                    'Media item added: type=${item['type']}, id=$itemId, '
                    'mime=$mimeType',
                  );
                  mediaBase64[itemId] = StringBuffer();
                  if (mimeType.isNotEmpty) mediaMime[itemId] = mimeType;
                }
              }
            } else if (currentEvent ==
                'response.function_call_arguments.delta') {
              final itemId = (data['item_id'] ?? '').toString();
              final argsDelta = (data['delta'] ?? '').toString();
              if (itemId.isNotEmpty && argsDelta.isNotEmpty) {
                final existingIndex = accumulatedToolCalls.indexWhere(
                  (t) => t.itemId == itemId,
                );
                if (existingIndex != -1) {
                  accumulatedToolCalls[existingIndex].argumentsJson +=
                      argsDelta;
                }
              }
            } else if (currentEvent == 'response.reasoning.delta' ||
                currentEvent == 'response.thinking.delta' ||
                currentEvent == 'response.reasoning_summary_text.delta' ||
                currentEvent == 'response.reasoning_summary.delta') {
              final delta = (data['delta'] ?? data['text'] ?? '').toString();
              if (delta.isNotEmpty) {
                reasoningBuffer.write(delta);
                reasoningDeltaBuffer.write(delta);
                // Emit a metadata-only thinking delta
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {'thinking': reasoningDeltaBuffer.toString()},
                  usage: lastResult.usage,
                );
                yield lastResult;
                reasoningDeltaBuffer.clear();
              }
            } else if (currentEvent == 'response.output_image.delta' ||
                currentEvent == 'response.output_audio.delta' ||
                currentEvent == 'response.image_generation.delta') {
              // Handle media deltas. Support either URL or base64 chunk forms.
              final itemId = (data['item_id'] ?? data['id'] ?? '').toString();
              final delta = data['delta'];
              // URL form
              String? url;
              String? mimeType;
              if (delta is Map<String, dynamic>) {
                url = (delta['image_url'] ?? delta['url'])?.toString();
                final mt = (delta['mime_type'] ?? data['mime_type'])
                    ?.toString();
                if (mt != null && mt.isNotEmpty) mimeType = mt;
                final b64 = (delta['data'] ?? delta['b64'] ?? '').toString();
                if (b64.isNotEmpty && itemId.isNotEmpty) {
                  (mediaBase64[itemId] ??= StringBuffer()).write(b64);
                }
              } else if (delta is String) {
                // Some implementations may stream raw base64 string
                if (itemId.isNotEmpty) {
                  (mediaBase64[itemId] ??= StringBuffer()).write(delta);
                }
              }

              if (url != null && url.isNotEmpty) {
                // Emit a link part immediately
                final message = ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [LinkPart(Uri.parse(url))],
                );
                final streamingMetadata = <String, dynamic>{};
                if (responseId != null) {
                  streamingMetadata['response_id'] = responseId;
                }
                if (containerId != null) {
                  streamingMetadata['container_id'] = containerId;
                }
                lastResult = ChatResult<ChatMessage>(
                  output: message,
                  messages: [message],
                  finishReason: FinishReason.unspecified,
                  metadata: streamingMetadata,
                  usage: lastResult.usage,
                );
                yield lastResult;
                // Also emit metadata-only hint for image_generation delta
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {
                    'image_generation': {'stage': 'delta', 'data': data},
                  },
                  usage: lastResult.usage,
                );
                yield lastResult;
              } else if (itemId.isNotEmpty &&
                  (mediaBase64[itemId]?.isNotEmpty ?? false)) {
                // Defer emission until completion event; keep accumulating
                if (mimeType != null && mimeType.isNotEmpty) {
                  mediaMime[itemId] = mimeType;
                }
                // Emit metadata for delta accumulation
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {
                    'image_generation': {'stage': 'delta', 'data': data},
                  },
                  usage: lastResult.usage,
                );
                yield lastResult;
              }
            } else if (currentEvent ==
                'response.image_generation_call.partial_image') {
              // Handle image_generation server-side tool partial image data
              final itemId = (data['item_id'] ?? data['id'] ?? '').toString();
              final b64 = (data['partial_image_b64'] ?? '').toString();
              if (b64.isNotEmpty && itemId.isNotEmpty) {
                _logger.info(
                  'Accumulating partial_image_b64 for item $itemId: '
                  '${b64.length} chars',
                );
                (mediaBase64[itemId] ??= StringBuffer()).write(b64);
                // image_generation produces PNGs
                mediaMime[itemId] = 'image/png';
                // Emit metadata for observability
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {
                    'image_generation': {
                      'stage': 'partial_image',
                      'data': data,
                    },
                  },
                  usage: lastResult.usage,
                );
                yield lastResult;
              }
            } else if (currentEvent == 'response.output_item.completed') {
              // Finalize any buffered media for this item
              final item = data['item'] as Map<String, dynamic>?;
              final itemId = (item?['id'] ?? data['item_id'] ?? '').toString();
              if (itemId.isNotEmpty &&
                  mediaBase64.containsKey(itemId) &&
                  mediaBase64[itemId]!.isNotEmpty) {
                try {
                  final b64String = mediaBase64[itemId]!.toString();
                  // Normalize base64 and remove all whitespace
                  final normalized = base64.normalize(
                    b64String.replaceAll(RegExp(r'\s+'), ''),
                  );
                  _logger.fine(
                    'Decoding base64 for output_item $itemId: '
                    '${normalized.length} chars',
                  );
                  final bytes = base64.decode(normalized);

                  final mimeType =
                      mediaMime[itemId] ??
                      (item?['mime_type']?.toString() ??
                          'application/octet-stream');

                  // Verify PNG signature if expected
                  if (bytes.length >= 8 && mimeType.contains('png')) {
                    _verifyPngSignature(bytes);
                  }

                  final message = ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [DataPart(bytes, mimeType: mimeType)],
                  );
                  final streamingMetadata = <String, dynamic>{};
                  if (responseId != null) {
                    streamingMetadata['response_id'] = responseId;
                  }
                  lastResult = ChatResult<ChatMessage>(
                    output: message,
                    messages: [message],
                    finishReason: FinishReason.unspecified,
                    metadata: streamingMetadata,
                    usage: lastResult.usage,
                  );
                  yield lastResult;
                } on Object catch (_) {
                  // Ignore decode errors silently; better than crashing stream
                } finally {
                  mediaBase64.remove(itemId);
                  mediaMime.remove(itemId);
                }
              }
            } else if (currentEvent == 'response.image_generation.completed') {
              // Finalize buffered image_generation media if any
              final itemId = (data['item_id'] ?? data['id'] ?? '').toString();
              if (itemId.isNotEmpty &&
                  mediaBase64.containsKey(itemId) &&
                  mediaBase64[itemId]!.isNotEmpty) {
                try {
                  final b64String = mediaBase64[itemId]!.toString();
                  // Normalize base64 and remove all whitespace
                  final normalized = base64.normalize(
                    b64String.replaceAll(RegExp(r'\s+'), ''),
                  );
                  _logger.fine(
                    'Decoding image_generation base64 for item $itemId: '
                    '${normalized.length} chars',
                  );
                  final bytes = base64.decode(normalized);

                  final mimeType = mediaMime[itemId] ?? 'image/png';
                  // Verify PNG signature since image_generation usually
                  // produces PNGs
                  if (bytes.length >= 8 && mimeType.contains('png')) {
                    _verifyPngSignature(bytes);
                  }

                  final message = ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [DataPart(bytes, mimeType: mimeType)],
                  );
                  final streamingMetadata = <String, dynamic>{};
                  if (responseId != null) {
                    streamingMetadata['response_id'] = responseId;
                  }
                  lastResult = ChatResult<ChatMessage>(
                    output: message,
                    messages: [message],
                    finishReason: FinishReason.unspecified,
                    metadata: streamingMetadata,
                    usage: lastResult.usage,
                  );
                  yield lastResult;
                } on Object catch (_) {
                  // ignore
                } finally {
                  mediaBase64.remove(itemId);
                  mediaMime.remove(itemId);
                }
              }
              // Emit completion metadata regardless
              lastResult = ChatResult<ChatMessage>(
                output: const ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [],
                ),
                messages: const [],
                finishReason: FinishReason.unspecified,
                metadata: {
                  'image_generation': {'stage': 'completed', 'data': data},
                },
                usage: lastResult.usage,
              );
              yield lastResult;
            } else if (currentEvent ==
                'response.image_generation_call.completed') {
              // Handle completion of image_generation server-side tool
              final itemId = (data['item_id'] ?? data['id'] ?? '').toString();
              if (itemId.isNotEmpty &&
                  mediaBase64.containsKey(itemId) &&
                  mediaBase64[itemId]!.isNotEmpty) {
                try {
                  final b64String = mediaBase64[itemId]!.toString();
                  // Normalize base64 and remove all whitespace
                  final normalized = base64.normalize(
                    b64String.replaceAll(RegExp(r'\s+'), ''),
                  );
                  _logger.fine(
                    'Decoding image_generation_call base64 for item $itemId: '
                    '${normalized.length} chars',
                  );
                  final bytes = base64.decode(normalized);

                  final mimeType = mediaMime[itemId] ?? 'image/png';
                  // Verify PNG signature
                  if (bytes.length >= 8 && mimeType.contains('png')) {
                    _verifyPngSignature(bytes);
                  }

                  final message = ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [DataPart(bytes, mimeType: mimeType)],
                  );
                  final streamingMetadata = <String, dynamic>{};
                  if (responseId != null) {
                    streamingMetadata['response_id'] = responseId;
                  }
                  lastResult = ChatResult<ChatMessage>(
                    output: message,
                    messages: [message],
                    finishReason: FinishReason.unspecified,
                    metadata: streamingMetadata,
                    usage: lastResult.usage,
                  );
                  yield lastResult;
                } on Object catch (_) {
                  // ignore
                } finally {
                  mediaBase64.remove(itemId);
                  mediaMime.remove(itemId);
                }
              }
              // Emit completion metadata
              lastResult = ChatResult<ChatMessage>(
                output: const ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [],
                ),
                messages: const [],
                finishReason: FinishReason.unspecified,
                metadata: {
                  'image_generation': {'stage': 'completed', 'data': data},
                },
                usage: lastResult.usage,
              );
              yield lastResult;
            } else if (currentEvent.startsWith('response.') &&
                currentEvent.contains('_call.') &&
                !currentEvent.startsWith('response.image_generation_call.')) {
              // Map server-side tool call lifecycle events, e.g.:
              // response.web_search_call.in_progress/searching/completed
              final afterPrefix = currentEvent.substring('response.'.length);
              final toolName = afterPrefix.split('_call').first; // web_search
              final stage = afterPrefix.contains('.')
                  ? afterPrefix.split('.').last
                  : 'in_progress';
              _logger.info('Server-side tool event: $toolName.$stage');
              lastResult = ChatResult<ChatMessage>(
                output: const ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [],
                ),
                messages: const [],
                finishReason: FinishReason.unspecified,
                metadata: {
                  toolName: {'stage': stage, 'data': data},
                },
                usage: lastResult.usage,
              );
              yield lastResult;
            } else if (currentEvent == 'response.completed') {
              // Do not emit consolidated text here to avoid duplication.
              // Orchestrator will consolidate state.accumulatedMessage.
              // Update usage if present so orchestrator can surface it.
              final resp = data['response'];
              if (resp is Map) {
                // Fallback: capture response ID if not already set
                if (responseId == null && resp.containsKey('id')) {
                  responseId = resp['id']?.toString();
                  _logger.info(
                    'Captured response ID from response.completed: '
                    '$responseId',
                  );
                }
                final u = resp['usage'];
                if (u is Map) {
                  lastResult = ChatResult<ChatMessage>(
                    output: lastResult.output,
                    messages: lastResult.messages,
                    finishReason: FinishReason.stop,
                    metadata: lastResult.metadata,
                    usage: LanguageModelUsage(
                      promptTokens:
                          (u['input_tokens'] ?? u['prompt_tokens']) as int?,
                      responseTokens:
                          (u['output_tokens'] ?? u['completion_tokens'])
                              as int?,
                      totalTokens: u['total_tokens'] as int?,
                    ),
                    id: lastResult.id,
                  );
                }
              }
            } else if (currentEvent == 'response.error' ||
                currentEvent == 'error') {
              throw Exception('OpenAI Responses stream error: $data');
            }

            currentEvent = null;
          }
          currentEvent = evName;
          _logger.info('Processing event: $evName');
        } else if (line.startsWith('data:')) {
          final dataLine = line.substring('data:'.length).trim();
          // Log data line (truncated) for debugging
          final preview = dataLine.length > 200
              ? '${dataLine.substring(0, 200)}…'
              : dataLine;
          _logger.fine('SSE data (event=${currentEvent ?? 'null'}): $preview');
          if (dataLine == '[DONE]') {
            // Stream finished marker; ignore here and let outer loop end
            continue;
          }

          // First-principles streaming: try to process this data line
          // immediately instead of waiting for the event boundary.
          try {
            final data = json.decode(dataLine) as Map<String, dynamic>;

            if (currentEvent == 'response.reasoning.delta' ||
                currentEvent == 'response.thinking.delta' ||
                currentEvent == 'response.reasoning_summary_text.delta' ||
                currentEvent == 'response.reasoning_summary.delta') {
              final delta = (data['delta'] ?? data['text'] ?? '').toString();
              if (delta.isNotEmpty) {
                reasoningBuffer.write(delta);
                reasoningDeltaBuffer.write(delta);

                // Emit reasoning immediately as metadata-only chunk
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {'thinking': reasoningDeltaBuffer.toString()},
                  usage: lastResult.usage,
                );
                yield lastResult;
                reasoningDeltaBuffer.clear();
                continue; // already handled this data line
              }
            }

            if (currentEvent == 'response.output_text.delta') {
              // Flush any pending reasoning before visible text
              if (reasoningDeltaBuffer.isNotEmpty) {
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {'thinking': reasoningDeltaBuffer.toString()},
                  usage: lastResult.usage,
                );
                yield lastResult;
                reasoningDeltaBuffer.clear();
              }

              final delta = (data['delta'] ?? data['text'] ?? '').toString();
              if (delta.isNotEmpty) {
                chunkCount++;
                accumulatedTextBuffer.write(delta);

                // Include response ID and container ID in message metadata
                final messageMetadata = <String, dynamic>{};
                if (responseId != null) {
                  messageMetadata['response_id'] = responseId;
                }
                if (containerId != null) {
                  messageMetadata['container_id'] = containerId;
                }

                final message = ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [TextPart(delta)],
                  metadata: messageMetadata,
                );
                lastResult = ChatResult<ChatMessage>(
                  output: message,
                  messages: [message],
                  finishReason: FinishReason.unspecified,
                  metadata: messageMetadata,
                  usage: lastResult.usage,
                );
                yield lastResult;
                continue; // handled immediately
              }
            } else if (currentEvent == 'response.output_image.delta' ||
                currentEvent == 'response.output_audio.delta' ||
                currentEvent == 'response.image_generation.delta') {
              // Allow immediate handling similar to text if URL present
              final data = json.decode(dataLine) as Map<String, dynamic>;
              final delta = data['delta'];
              final itemId = (data['item_id'] ?? data['id'] ?? '').toString();
              if (delta is Map<String, dynamic>) {
                final url = (delta['image_url'] ?? delta['url'])?.toString();
                final mt = (delta['mime_type'] ?? data['mime_type'])
                    ?.toString();
                if (url != null && url.isNotEmpty) {
                  final message = ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [LinkPart(Uri.parse(url))],
                  );
                  lastResult = ChatResult<ChatMessage>(
                    output: message,
                    messages: [message],
                    finishReason: FinishReason.unspecified,
                    metadata: const {},
                    usage: lastResult.usage,
                  );
                  yield lastResult;
                  // Metadata hint for image_generation delta
                  lastResult = ChatResult<ChatMessage>(
                    output: const ChatMessage(
                      role: ChatMessageRole.model,
                      parts: [],
                    ),
                    messages: const [],
                    finishReason: FinishReason.unspecified,
                    metadata: {
                      'image_generation': {'stage': 'delta', 'data': data},
                    },
                    usage: lastResult.usage,
                  );
                  yield lastResult;
                  continue; // handled immediately
                }
                final b64 = (delta['data'] ?? delta['b64'] ?? '').toString();
                if (b64.isNotEmpty && itemId.isNotEmpty) {
                  (mediaBase64[itemId] ??= StringBuffer()).write(b64);
                  if (mt != null && mt.isNotEmpty) mediaMime[itemId] = mt;
                  // Metadata hint for accumulation delta
                  lastResult = ChatResult<ChatMessage>(
                    output: const ChatMessage(
                      role: ChatMessageRole.model,
                      parts: [],
                    ),
                    messages: const [],
                    finishReason: FinishReason.unspecified,
                    metadata: {
                      'image_generation': {'stage': 'delta', 'data': data},
                    },
                    usage: lastResult.usage,
                  );
                  yield lastResult;
                }
              } else if (delta is String && itemId.isNotEmpty) {
                (mediaBase64[itemId] ??= StringBuffer()).write(delta);
              }
            } else if (currentEvent ==
                'response.image_generation_call.partial_image') {
              // Handle immediate processing of partial image data
              final itemId = (data['item_id'] ?? data['id'] ?? '').toString();
              final b64 = (data['partial_image_b64'] ?? '').toString();
              if (b64.isNotEmpty && itemId.isNotEmpty) {
                _logger.info(
                  'Accumulating partial_image_b64 for item $itemId: '
                  '${b64.length} chars',
                );
                (mediaBase64[itemId] ??= StringBuffer()).write(b64);
                // image_generation produces PNGs
                mediaMime[itemId] = 'image/png';
                // Emit metadata for observability
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {
                    'image_generation': {
                      'stage': 'partial_image',
                      'data': data,
                    },
                  },
                  usage: lastResult.usage,
                );
                yield lastResult;
                continue; // handled immediately
              }
            } else if (currentEvent ==
                'response.image_generation_call.completed') {
              // Handle immediate completion of image generation
              final itemId = (data['item_id'] ?? data['id'] ?? '').toString();
              if (itemId.isNotEmpty &&
                  mediaBase64.containsKey(itemId) &&
                  mediaBase64[itemId]!.isNotEmpty) {
                try {
                  final b64String = mediaBase64[itemId]!.toString();
                  // Normalize base64 and remove all whitespace
                  final normalized = base64.normalize(
                    b64String.replaceAll(RegExp(r'\s+'), ''),
                  );
                  _logger.fine(
                    'Decoding image_generation_call base64 for item $itemId: '
                    '${normalized.length} chars',
                  );
                  final bytes = base64.decode(normalized);

                  final mimeType = mediaMime[itemId] ?? 'image/png';
                  // Verify PNG signature
                  if (bytes.length >= 8 && mimeType.contains('png')) {
                    _verifyPngSignature(bytes);
                  }

                  final message = ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [DataPart(bytes, mimeType: mimeType)],
                  );
                  final streamingMetadata = <String, dynamic>{};
                  if (responseId != null) {
                    streamingMetadata['response_id'] = responseId;
                  }
                  lastResult = ChatResult<ChatMessage>(
                    output: message,
                    messages: [message],
                    finishReason: FinishReason.unspecified,
                    metadata: streamingMetadata,
                    usage: lastResult.usage,
                  );
                  yield lastResult;
                } on Object catch (_) {
                  // ignore
                } finally {
                  mediaBase64.remove(itemId);
                  mediaMime.remove(itemId);
                }
              }
              // Emit completion metadata
              lastResult = ChatResult<ChatMessage>(
                output: const ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [],
                ),
                messages: const [],
                finishReason: FinishReason.unspecified,
                metadata: {
                  'image_generation': {'stage': 'completed', 'data': data},
                },
                usage: lastResult.usage,
              );
              yield lastResult;
              continue; // handled immediately
            } else if (currentEvent == 'response.web_search.started' ||
                currentEvent == 'response.file_search.started' ||
                currentEvent == 'response.computer_use.started' ||
                currentEvent == 'response.code_interpreter.started') {
              final parts = currentEvent!.split('.');
              final t = parts.length > 1 ? parts[1] : 'tool';
              lastResult = ChatResult<ChatMessage>(
                output: const ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [],
                ),
                messages: const [],
                finishReason: FinishReason.unspecified,
                metadata: {
                  t: {'stage': 'started', 'data': data},
                },
                usage: lastResult.usage,
              );
              yield lastResult;
              continue;
            } else if (currentEvent == 'response.output_item.added' ||
                currentEvent == 'response.output_item.done') {
              // Handle output_item events which contain container_id for
              // code_interpreter
              final itemData = data['item'];
              if (itemData != null && 
                  itemData is Map &&
                  itemData['type'] == 'code_interpreter_call') {
                final itemContainerId = itemData['container_id'];
                final code = itemData['code'];
                
                // Capture the container ID for message metadata
                if (itemContainerId != null) {
                  containerId = itemContainerId as String;
                }
                
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {
                    'code_interpreter': {
                      'stage': currentEvent == 'response.output_item.added' 
                          ? 'started' 
                          : 'completed',
                      'data': {
                        if (itemContainerId != null) 
                          'container_id': itemContainerId,
                        if (code != null) 'code': code,
                      },
                    },
                  },
                  usage: lastResult.usage,
                );
                yield lastResult;
                continue;
              } else if (itemData != null &&
                  itemData is Map &&
                  itemData['type'] == 'message') {
                // Handle message items that may contain annotations
                final content = itemData['content'];
                if (content is List) {
                  for (final part in content) {
                    if (part is Map) {
                      final annotations = part['annotations'];
                      if (annotations is List && annotations.isNotEmpty) {
                        // Extract file citations from annotations
                        final fileCitations = <Map<String, dynamic>>[];
                        for (final ann in annotations) {
                          if (ann is Map && 
                              ann['type'] == 'container_file_citation') {
                            fileCitations.add({
                              'container_id': ann['container_id'],
                              'file_id': ann['file_id'],
                              'filename': ann['filename'],
                            });
                          }
                        }
                        if (fileCitations.isNotEmpty) {
                          lastResult = ChatResult<ChatMessage>(
                            output: const ChatMessage(
                              role: ChatMessageRole.model,
                              parts: [],
                            ),
                            messages: const [],
                            finishReason: FinishReason.unspecified,
                            metadata: {
                              'code_interpreter': {
                                'stage': 'files_generated',
                                'data': {
                                  'files': fileCitations,
                                },
                              },
                            },
                            usage: lastResult.usage,
                          );
                          yield lastResult;
                        }
                      }
                    }
                  }
                }
              }
            } else if (currentEvent == 'response.web_search.result' ||
                currentEvent == 'response.file_search.result' ||
                currentEvent == 'response.computer_use.action' ||
                currentEvent == 'response.computer_use.result' ||
                currentEvent == 'response.code_interpreter.output' ||
                currentEvent == 'response.code_interpreter_call.in_progress' ||
                currentEvent == 'response.code_interpreter_call.interpreting' ||
                currentEvent == 'response.code_interpreter_call.completed' ||
                currentEvent == 'response.code_interpreter_call_code.delta' ||
                currentEvent == 'response.code_interpreter_call_code.done') {
              final parts = currentEvent!.split('.');
              // For code_interpreter_call events, normalize the tool name
              String t;
              String stage;
              if (parts[1].startsWith('code_interpreter_call')) {
                t = 'code_interpreter';
                // Extract stage from event like
                // 'response.code_interpreter_call.in_progress'
                // or 'response.code_interpreter_call_code.delta'
                if (parts[1] == 'code_interpreter_call') {
                  stage = parts.length > 2 ? parts[2] : 'data';
                } else if (parts[1] == 'code_interpreter_call_code') {
                  stage = 'code_${parts.length > 2 ? parts[2] : "data"}';
                } else {
                  stage = 'data';
                }
              } else {
                t = parts.length > 1 ? parts[1] : 'tool';
                stage = parts.length > 2 ? parts[2] : 'data';
              }
              lastResult = ChatResult<ChatMessage>(
                output: const ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [],
                ),
                messages: const [],
                finishReason: FinishReason.unspecified,
                metadata: {
                  t: {'stage': stage, 'data': data},
                },
                usage: lastResult.usage,
              );
              yield lastResult;
              continue;
            }

            // For other events (e.g., tool_call deltas), fall back to
            // boundary-based handling by buffering this data
            if (dataBuffer.isNotEmpty) dataBuffer.write('\n');
            dataBuffer.write(dataLine);
          } on Object {
            // If JSON parsing fails, buffer and let boundary handler process
            if (dataBuffer.isNotEmpty) dataBuffer.write('\n');
            dataBuffer.write(dataLine);
          }
        } else if (line.isEmpty) {
          // Event delimiter: flush current event
          if (currentEvent != null) {
            final dataStr = dataBuffer.toString();
            dataBuffer.clear();

            if (dataStr.trim().isEmpty) {
              currentEvent = null;
              continue;
            }

            Map<String, dynamic> data;
            try {
              data = json.decode(dataStr) as Map<String, dynamic>;
            } on Object {
              // Skip malformed/incomplete JSON safely
              currentEvent = null;
              continue;
            }

            // Duplicate handling to flush on empty line
            // If this is an event type we already processed line-by-line,
            // skip any boundary flush processing to avoid duplicate output.
            if (currentEvent == 'response.reasoning.delta' ||
                currentEvent == 'response.thinking.delta' ||
                currentEvent == 'response.reasoning_summary_text.delta' ||
                currentEvent == 'response.reasoning_summary.delta') {
              currentEvent = null;
              continue;
            } else if (currentEvent == 'response.output_text.delta') {
              // If there is pending reasoning delta, emit it BEFORE text
              if (reasoningDeltaBuffer.isNotEmpty) {
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {'thinking': reasoningDeltaBuffer.toString()},
                  usage: lastResult.usage,
                );
                yield lastResult;
                reasoningDeltaBuffer.clear();
              }
              final delta = (data['delta'] ?? data['text'] ?? '').toString();
              if (delta.isNotEmpty) {
                chunkCount++;
                accumulatedTextBuffer.write(delta);
                // Include response ID and container ID in metadata if available
                final streamingMetadata = <String, dynamic>{};
                if (reasoningDeltaBuffer.isNotEmpty) {
                  streamingMetadata['thinking'] = reasoningDeltaBuffer
                      .toString();
                }
                if (responseId != null) {
                  streamingMetadata['response_id'] = responseId;
                }
                if (containerId != null) {
                  streamingMetadata['container_id'] = containerId;
                }
                
                final message = ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [TextPart(delta)],
                  metadata: streamingMetadata,
                );

                lastResult = ChatResult<ChatMessage>(
                  output: message,
                  messages: [message],
                  finishReason: FinishReason.unspecified,
                  metadata: streamingMetadata,
                  usage: lastResult.usage,
                );
                yield lastResult;
                reasoningDeltaBuffer.clear();
              }
            } else if (currentEvent == 'response.output_item.added') {
              final item = data['item'] as Map<String, dynamic>?;
              if (item?['type'] == 'function_call') {
                final callId = (item?['call_id'] ?? '').toString();
                final name = (item?['name'] ?? '').toString();
                final itemId = (item?['id'] ?? '').toString();

                if (callId.isNotEmpty && name.isNotEmpty && itemId.isNotEmpty) {
                  _logger.info(
                    'Tool call added: '
                    'callId=$callId, name=$name, itemId=$itemId',
                  );
                  // Use item_id as the key for matching arguments later
                  accumulatedToolCalls.add(
                    StreamingToolCall(
                      // Use callId as primary ID to match function_call_output
                      id: callId,
                      name: name,
                      itemId: itemId,
                    ),
                  );
                }
              } else if (item != null &&
                  (item['type'] == 'image' ||
                      item['type'] == 'output_image' ||
                      item['type'] == 'audio' ||
                      item['type'] == 'output_audio')) {
                final itemId = (item['id'] ?? '').toString();
                final mimeType = (item['mime_type'] ?? '').toString();
                if (itemId.isNotEmpty) {
                  _logger.info(
                    'Media item added (boundary): type=${item['type']}, '
                    'id=$itemId, mime=$mimeType',
                  );
                  mediaBase64[itemId] = StringBuffer();
                  if (mimeType.isNotEmpty) mediaMime[itemId] = mimeType;
                }
              }
            } else if (currentEvent ==
                'response.function_call_arguments.delta') {
              final itemId = (data['item_id'] ?? '').toString();
              final argsDelta = (data['delta'] ?? '').toString();
              if (itemId.isNotEmpty && argsDelta.isNotEmpty) {
                final existingIndex = accumulatedToolCalls.indexWhere(
                  (t) => t.itemId == itemId,
                );
                if (existingIndex != -1) {
                  accumulatedToolCalls[existingIndex].argumentsJson +=
                      argsDelta;
                }
              }
            } else if (currentEvent == 'response.reasoning.delta' ||
                currentEvent == 'response.thinking.delta' ||
                currentEvent == 'response.reasoning_summary_text.delta' ||
                currentEvent == 'response.reasoning_summary.delta') {
              final delta = (data['delta'] ?? data['text'] ?? '').toString();
              if (delta.isNotEmpty) {
                reasoningBuffer.write(delta);
                reasoningDeltaBuffer.write(delta);
                // Emit a metadata-only thinking delta
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {'thinking': reasoningDeltaBuffer.toString()},
                  usage: lastResult.usage,
                );
                yield lastResult;
                reasoningDeltaBuffer.clear();
              }
            } else if (currentEvent == 'response.output_image.delta' ||
                currentEvent == 'response.output_audio.delta' ||
                currentEvent == 'response.image_generation.delta') {
              final itemId = (data['item_id'] ?? data['id'] ?? '').toString();
              final delta = data['delta'];
              String? url;
              String? mimeType;
              if (delta is Map<String, dynamic>) {
                url = (delta['image_url'] ?? delta['url'])?.toString();
                final mt = (delta['mime_type'] ?? data['mime_type'])
                    ?.toString();
                if (mt != null && mt.isNotEmpty) mimeType = mt;
                final b64 = (delta['data'] ?? delta['b64'] ?? '').toString();
                if (b64.isNotEmpty && itemId.isNotEmpty) {
                  (mediaBase64[itemId] ??= StringBuffer()).write(b64);
                }
              } else if (delta is String && itemId.isNotEmpty) {
                (mediaBase64[itemId] ??= StringBuffer()).write(delta);
              }

              if (url != null && url.isNotEmpty) {
                final message = ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [LinkPart(Uri.parse(url))],
                );
                lastResult = ChatResult<ChatMessage>(
                  output: message,
                  messages: [message],
                  finishReason: FinishReason.unspecified,
                  metadata: const {},
                  usage: lastResult.usage,
                );
                yield lastResult;
              } else if (itemId.isNotEmpty &&
                  mimeType != null &&
                  mimeType.isNotEmpty) {
                mediaMime[itemId] = mimeType;
              }
            } else if (currentEvent == 'response.image_generation.completed') {
              final itemId = (data['item_id'] ?? data['id'] ?? '').toString();
              if (itemId.isNotEmpty &&
                  mediaBase64.containsKey(itemId) &&
                  mediaBase64[itemId]!.isNotEmpty) {
                try {
                  final b64String = mediaBase64[itemId]!.toString();
                  // Normalize base64 and remove all whitespace
                  final normalized = base64.normalize(
                    b64String.replaceAll(RegExp(r'\s+'), ''),
                  );
                  _logger.fine(
                    'Decoding image_generation base64 (boundary) for '
                    'item $itemId: '
                    '${normalized.length} chars',
                  );
                  final bytes = base64.decode(normalized);

                  final mimeType = mediaMime[itemId] ?? 'image/png';
                  // Verify PNG signature
                  if (bytes.length >= 8 && mimeType.contains('png')) {
                    _verifyPngSignature(bytes);
                  }

                  final message = ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [DataPart(bytes, mimeType: mimeType)],
                  );
                  lastResult = ChatResult<ChatMessage>(
                    output: message,
                    messages: [message],
                    finishReason: FinishReason.unspecified,
                    metadata: const {},
                    usage: lastResult.usage,
                  );
                  yield lastResult;
                } on Object catch (_) {
                  // Ignore
                } finally {
                  mediaBase64.remove(itemId);
                  mediaMime.remove(itemId);
                }
              }
              // Emit completion metadata
              lastResult = ChatResult<ChatMessage>(
                output: const ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [],
                ),
                messages: const [],
                finishReason: FinishReason.unspecified,
                metadata: {
                  'image_generation': {'stage': 'completed', 'data': data},
                },
                usage: lastResult.usage,
              );
              yield lastResult;
            } else if (currentEvent.startsWith('response.') &&
                currentEvent.contains('_call.')) {
              final afterPrefix = currentEvent.substring('response.'.length);
              final tool = afterPrefix.split('_call').first;
              final stage = afterPrefix.contains('.')
                  ? afterPrefix.split('.').last
                  : 'in_progress';
              _logger.fine('Server-side tool event (boundary): $tool.$stage');
              lastResult = ChatResult<ChatMessage>(
                output: const ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [],
                ),
                messages: const [],
                finishReason: FinishReason.unspecified,
                metadata: {
                  tool: {'stage': stage, 'data': data},
                },
                usage: lastResult.usage,
              );
              yield lastResult;
            } else if (currentEvent == 'response.output_item.completed') {
              final item = data['item'] as Map<String, dynamic>?;
              final itemId = (item?['id'] ?? data['item_id'] ?? '').toString();
              if (itemId.isNotEmpty &&
                  mediaBase64.containsKey(itemId) &&
                  mediaBase64[itemId]!.isNotEmpty) {
                try {
                  final b64String = mediaBase64[itemId]!.toString();
                  // Normalize base64 and remove all whitespace
                  final normalized = base64.normalize(
                    b64String.replaceAll(RegExp(r'\s+'), ''),
                  );
                  _logger.fine(
                    'Decoding base64 (boundary) for output_item $itemId: '
                    '${normalized.length} chars',
                  );
                  final bytes = base64.decode(normalized);

                  final mimeType =
                      mediaMime[itemId] ??
                      (item?['mime_type']?.toString() ??
                          'application/octet-stream');

                  // Verify PNG signature if expected
                  if (bytes.length >= 8 && mimeType.contains('png')) {
                    _verifyPngSignature(bytes);
                  }

                  final message = ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [DataPart(bytes, mimeType: mimeType)],
                  );
                  lastResult = ChatResult<ChatMessage>(
                    output: message,
                    messages: [message],
                    finishReason: FinishReason.unspecified,
                    metadata: const {},
                    usage: lastResult.usage,
                  );
                  yield lastResult;
                } on Object catch (_) {
                  // Ignore decode errors
                } finally {
                  mediaBase64.remove(itemId);
                  mediaMime.remove(itemId);
                }
              }
              // Also surface completion for server-side calls via item.type
              final itemType = item?['type']?.toString() ?? '';
              if (itemType.endsWith('_call')) {
                final tool = itemType.replaceAll('_call', '');
                lastResult = ChatResult<ChatMessage>(
                  output: const ChatMessage(
                    role: ChatMessageRole.model,
                    parts: [],
                  ),
                  messages: const [],
                  finishReason: FinishReason.unspecified,
                  metadata: {
                    tool: {'stage': 'completed', 'data': data},
                  },
                  usage: lastResult.usage,
                );
                yield lastResult;
              }
            } else if (currentEvent == 'response.created') {
              // Capture response ID from response.created event
              final resp = data['response'];
              if (responseId == null &&
                  resp is Map<String, dynamic> &&
                  resp.containsKey('id')) {
                responseId = resp['id']?.toString();
                _logger.info(
                  'Captured response ID from response.created (boundary): '
                  '$responseId',
                );
              }
            } else if (currentEvent == 'response.completed') {
              // Do not re-emit consolidated output; orchestrator will handle.
              final resp = data['response'];
              if (resp is Map) {
                // Fallback: capture response ID if not already set
                if (responseId == null && resp.containsKey('id')) {
                  responseId = resp['id']?.toString();
                  _logger.info(
                    'Captured response ID from response.completed '
                    '(boundary): $responseId',
                  );
                }
                final u = resp['usage'];
                if (u is Map) {
                  lastResult = ChatResult<ChatMessage>(
                    output: lastResult.output,
                    messages: lastResult.messages,
                    finishReason: FinishReason.stop,
                    metadata: lastResult.metadata,
                    usage: LanguageModelUsage(
                      promptTokens:
                          (u['input_tokens'] ?? u['prompt_tokens']) as int?,
                      responseTokens:
                          (u['output_tokens'] ?? u['completion_tokens'])
                              as int?,
                      totalTokens: u['total_tokens'] as int?,
                    ),
                    id: lastResult.id,
                  );
                }
              }
            } else if (currentEvent == 'response.error' ||
                currentEvent == 'error') {
              throw Exception('OpenAI Responses stream error: $data');
            }

            currentEvent = null;
          }
        }
      }

      _logger.info(
        'OpenAI Responses stream completed after $chunkCount chunks',
      );

      // After streaming completes, create and yield the final message with all
      // tools
      if (accumulatedToolCalls.isNotEmpty) {
        final completeMessage = createCompleteMessageWithTools(
          accumulatedToolCalls,
          accumulatedText: accumulatedTextBuffer.toString(),
        );

        // Include response ID and container ID in metadata
        final messageMetadata = <String, dynamic>{};
        if (responseId != null) {
          messageMetadata['response_id'] = responseId;
        }
        if (containerId != null) {
          messageMetadata['container_id'] = containerId;
        }

        // Create message with metadata
        final messageWithMetadata = ChatMessage(
          role: completeMessage.role,
          parts: completeMessage.parts,
          metadata: messageMetadata,
        );

        yield ChatResult<ChatMessage>(
          id: lastResult.id,
          output: messageWithMetadata,
          messages: [messageWithMetadata],
          finishReason: lastResult.finishReason,
          metadata: messageMetadata,
          usage: lastResult.usage,
        );
      }
    } catch (e) {
      _logger.warning('OpenAI Responses stream error: $e');
      rethrow;
    } finally {
      // no-op
    }
  }

  @override
  void dispose() {
    // Close HTTP client session
    _client.close();
  }

  /// Verifies PNG signature for image data
  static void _verifyPngSignature(List<int> bytes) {
    // PNG signature: 89 50 4E 47 0D 0A 1A 0A
    const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    if (bytes.length < 8) {
      _logger.warning('Image data too short to be a valid PNG');
      return;
    }

    for (var i = 0; i < 8; i++) {
      if (bytes[i] != pngSignature[i]) {
        _logger.warning(
          'Invalid PNG signature at byte $i: expected ${pngSignature[i]}, '
          'got ${bytes[i]}',
        );
        return;
      }
    }

    _logger.fine('Valid PNG signature verified');
  }
}
