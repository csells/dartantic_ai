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
import 'openai_responses_chat_options.dart';
import 'openai_responses_message_mappers.dart';

/// Chat model backed by the OpenAI Responses API (streaming).
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

    final payload = buildResponsesRequest(
      messages,
      modelName: name,
      tools: tools,
      temperature: temperature,
      defaultOptions: defaultOptions,
      options: options,
      outputSchema: outputSchema,
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
    request.headers.addAll({
      if (_apiKey != null && _apiKey.isNotEmpty)
        'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      // Required beta header for Responses API
      'OpenAI-Beta': 'responses=v1',
      ...?_headers,
    });

    request.body = json.encode(payload);

    final accumulatedToolCalls = <StreamingToolCall>[];
    final accumulatedTextBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    final reasoningDeltaBuffer = StringBuffer();
    var chunkCount = 0;

    var lastResult = ChatResult<ChatMessage>(
      output: const ChatMessage(role: ChatMessageRole.model, parts: []),
      finishReason: FinishReason.unspecified,
      metadata: const {},
      usage: const LanguageModelUsage(),
    );

    http.StreamedResponse? streamedResponse;
    try {
      streamedResponse = await _client.send(request);
      if (streamedResponse.statusCode != 200) {
        final body = await streamedResponse.stream.bytesToString();
        throw Exception(
          'OpenAI Responses error: HTTP ${streamedResponse.statusCode}: $body',
        );
      }

      String? currentEvent;
      final dataBuffer = StringBuffer();

      final lines = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (line.startsWith('event:')) {
          // Process any pending event before switching
          if (currentEvent != null) {
            final dataStr = dataBuffer.toString();
            dataBuffer.clear();

            final data = json.decode(dataStr) as Map<String, dynamic>;

            // Handle previous event
            if (currentEvent == 'response.output_text.delta') {
              final delta = (data['delta'] ?? data['text'] ?? '').toString();
              if (delta.isNotEmpty) {
                chunkCount++;
                accumulatedTextBuffer.write(delta);

                final message = ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [TextPart(delta)],
                );
                lastResult = ChatResult<ChatMessage>(
                  output: message,
                  messages: [message],
                  finishReason: FinishReason.unspecified,
                  metadata: reasoningDeltaBuffer.isEmpty
                      ? const {}
                      : {'thinking': reasoningDeltaBuffer.toString()},
                  usage: lastResult.usage,
                );
                yield lastResult;
                reasoningDeltaBuffer.clear();
              }
            } else if (currentEvent == 'response.tool_call.delta') {
              final id = (data['id'] ?? data['tool_call_id'] ?? '').toString();
              final name = (data['name'] ?? '').toString();
              final argsDelta = (data['arguments_delta'] ?? data['delta'] ?? '')
                  .toString();
              if (id.isNotEmpty) {
                final existingIndex = accumulatedToolCalls.indexWhere(
                  (t) => t.id == id,
                );
                StreamingToolCall sc;
                if (existingIndex == -1) {
                  sc = StreamingToolCall(id: id, name: name);
                  accumulatedToolCalls.add(sc);
                } else {
                  sc = accumulatedToolCalls[existingIndex];
                }
                if (name.isNotEmpty) sc.name = name;
                if (argsDelta.isNotEmpty) sc.argumentsJson += argsDelta;
              }
            } else if (currentEvent == 'response.tool_call.created') {
              final id = (data['id'] ?? '').toString();
              final name = (data['name'] ?? '').toString();
              if (id.isNotEmpty) {
                accumulatedToolCalls.add(StreamingToolCall(id: id, name: name));
              }
            } else if (currentEvent == 'response.reasoning.delta' ||
                currentEvent == 'response.thinking.delta' ||
                currentEvent == 'response.reasoning_summary_text.delta') {
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
            } else if (currentEvent == 'response.completed') {
              // Finalize and yield
              if (accumulatedToolCalls.isNotEmpty ||
                  accumulatedTextBuffer.isNotEmpty) {
                final completeMessage = createCompleteMessageWithTools(
                  accumulatedToolCalls,
                  accumulatedText: accumulatedTextBuffer.toString(),
                );

                // Extract usage if present
                var usage = lastResult.usage;
                final resp = data['response'];
                if (resp is Map) {
                  final u = resp['usage'];
                  if (u is Map) {
                    usage = LanguageModelUsage(
                      promptTokens:
                          (u['input_tokens'] ?? u['prompt_tokens']) as int?,
                      responseTokens:
                          (u['output_tokens'] ?? u['completion_tokens'])
                              as int?,
                      totalTokens: u['total_tokens'] as int?,
                    );
                  }
                }

                yield ChatResult<ChatMessage>(
                  id: lastResult.id,
                  output: completeMessage,
                  messages: [completeMessage],
                  finishReason: FinishReason.stop,
                  metadata: {
                    ...lastResult.metadata,
                    if (reasoningBuffer.isNotEmpty)
                      'thinking': reasoningBuffer.toString(),
                  },
                  usage: usage,
                );
              } else {
                yield lastResult;
              }
            } else if (currentEvent == 'response.error' ||
                currentEvent == 'error') {
              throw Exception('OpenAI Responses stream error: $data');
            }

            currentEvent = null;
          }

          currentEvent = line.substring('event:'.length).trim();
        } else if (line.startsWith('data:')) {
          final data = line.substring('data:'.length).trim();
          if (data == '[DONE]') {
            // Treat as event boundary flush; no explicit action
            continue;
          }
          if (dataBuffer.isNotEmpty) dataBuffer.write('\n');
          dataBuffer.write(data);
        } else if (line.isEmpty) {
          // Event delimiter: flush current event
          if (currentEvent != null) {
            final dataStr = dataBuffer.toString();
            dataBuffer.clear();

            final data = json.decode(dataStr) as Map<String, dynamic>;

            // Duplicate handling to flush on empty line
            if (currentEvent == 'response.output_text.delta') {
              final delta = (data['delta'] ?? data['text'] ?? '').toString();
              if (delta.isNotEmpty) {
                chunkCount++;
                accumulatedTextBuffer.write(delta);
                final message = ChatMessage(
                  role: ChatMessageRole.model,
                  parts: [TextPart(delta)],
                );
                lastResult = ChatResult<ChatMessage>(
                  output: message,
                  messages: [message],
                  finishReason: FinishReason.unspecified,
                  metadata: reasoningDeltaBuffer.isEmpty
                      ? const {}
                      : {'thinking': reasoningDeltaBuffer.toString()},
                  usage: lastResult.usage,
                );
                yield lastResult;
                reasoningDeltaBuffer.clear();
              }
            } else if (currentEvent == 'response.tool_call.delta') {
              final id = (data['id'] ?? data['tool_call_id'] ?? '').toString();
              final name = (data['name'] ?? '').toString();
              final argsDelta = (data['arguments_delta'] ?? data['delta'] ?? '')
                  .toString();
              if (id.isNotEmpty) {
                final existingIndex = accumulatedToolCalls.indexWhere(
                  (t) => t.id == id,
                );
                StreamingToolCall sc;
                if (existingIndex == -1) {
                  sc = StreamingToolCall(id: id, name: name);
                  accumulatedToolCalls.add(sc);
                } else {
                  sc = accumulatedToolCalls[existingIndex];
                }
                if (name.isNotEmpty) sc.name = name;
                if (argsDelta.isNotEmpty) sc.argumentsJson += argsDelta;
              }
            } else if (currentEvent == 'response.tool_call.created') {
              final id = (data['id'] ?? '').toString();
              final name = (data['name'] ?? '').toString();
              if (id.isNotEmpty) {
                accumulatedToolCalls.add(StreamingToolCall(id: id, name: name));
              }
            } else if (currentEvent == 'response.reasoning.delta' ||
                currentEvent == 'response.thinking.delta' ||
                currentEvent == 'response.reasoning_summary_text.delta') {
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
            } else if (currentEvent == 'response.completed') {
              if (accumulatedToolCalls.isNotEmpty ||
                  accumulatedTextBuffer.isNotEmpty) {
                final completeMessage = createCompleteMessageWithTools(
                  accumulatedToolCalls,
                  accumulatedText: accumulatedTextBuffer.toString(),
                );

                var usage = lastResult.usage;
                final resp = data['response'];
                if (resp is Map) {
                  final u = resp['usage'];
                  if (u is Map) {
                    usage = LanguageModelUsage(
                      promptTokens:
                          (u['input_tokens'] ?? u['prompt_tokens']) as int?,
                      responseTokens:
                          (u['output_tokens'] ?? u['completion_tokens'])
                              as int?,
                      totalTokens: u['total_tokens'] as int?,
                    );
                  }
                }

                yield ChatResult<ChatMessage>(
                  id: lastResult.id,
                  output: completeMessage,
                  messages: [completeMessage],
                  finishReason: FinishReason.stop,
                  metadata: {
                    ...lastResult.metadata,
                    if (reasoningBuffer.isNotEmpty)
                      'thinking': reasoningBuffer.toString(),
                  },
                  usage: usage,
                );
              } else {
                yield lastResult;
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
}
