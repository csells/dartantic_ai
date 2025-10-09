import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:openai_dart/openai_dart.dart';

import '../../agent/tool_constants.dart';
import '../../retry_http_client.dart';
import 'openai_chat_options.dart';
import 'openai_message_mappers.dart';
import 'openai_message_mappers_helpers.dart';

/// Wrapper around [OpenAI Chat
/// API](https://platform.openai.com/docs/api-reference/chat).
class OpenAIChatModel extends ChatModel<OpenAIChatOptions> {
  /// Creates a [OpenAIChatModel] instance.
  OpenAIChatModel({
    required super.name,
    String? apiKey,
    List<Tool>? tools,
    super.temperature,
    OpenAIChatOptions? defaultOptions,
    String? organization,
    Uri? baseUrl,
    Map<String, String>? headers,
    Map<String, dynamic>? queryParams,
    http.Client? client,
  }) : _client = OpenAIClient(
         apiKey: apiKey,
         organization: organization,
         baseUrl: baseUrl?.toString(),
         headers: headers,
         queryParams: queryParams,
         client: client != null
             ? RetryHttpClient(inner: client)
             : RetryHttpClient(inner: http.Client()),
       ),
       super(
         defaultOptions: defaultOptions ?? const OpenAIChatOptions(),
         // Filter out return_result tool as OpenAI has native typed output
         // support
         tools: () {
           if (tools == null) return null;
           final filtered = tools
               .where((t) => t.name != kReturnResultToolName)
               .toList();
           return filtered.isEmpty ? null : filtered;
         }(),
       ) {
    // Validate that providers with known tool limitations don't use tools
    // Check the original tools parameter BEFORE filtering
    if (tools != null && tools.isNotEmpty) {
      final normalizedBaseUrl = baseUrl?.toString().toLowerCase() ?? '';

      // Together AI doesn't support OpenAI-style tool calls
      // Exception: Allow return_result tool for typed output support
      if (normalizedBaseUrl.contains('together.xyz')) {
        final hasOnlyReturnResult =
            tools.length == 1 && tools.first.name == kReturnResultToolName;

        if (!hasOnlyReturnResult) {
          throw ArgumentError(
            'Together AI does not support OpenAI-compatible tool calls. '
            'Their streaming API returns tools in a custom format with '
            '<|python_tag|> prefix instead of standard tool_calls.',
          );
        }

        // If only return_result tool, we'll filter it out and use
        // response_format
      }
    }
  }

  /// Logger for OpenAI chat model operations.
  static final Logger _logger = Logger('dartantic.chat.models.openai');

  final OpenAIClient _client;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    OpenAIChatOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    _logger.info(
      'Starting OpenAI chat stream with ${messages.length} messages '
      'for model: $name',
    );

    final request = createChatCompletionRequest(
      messages,
      modelName: name,
      tools: tools,
      temperature: temperature,
      options: options,
      defaultOptions: defaultOptions,
      outputSchema: outputSchema,
    );

    final accumulatedToolCalls = <StreamingToolCall>[];
    final accumulatedTextBuffer = StringBuffer();
    var chunkCount = 0;
    var lastResult = ChatResult<ChatMessage>(
      output: const ChatMessage(role: ChatMessageRole.model, parts: []),
      finishReason: FinishReason.unspecified,
      metadata: const {},
      usage: null,
    );

    try {
      await for (final completion in _client.createChatCompletionStream(
        request: request,
      )) {
        chunkCount++;
        _logger.fine('Received OpenAI stream chunk $chunkCount');
        final delta = completion.choices?.firstOrNull?.delta;

        // Update usage if present (even if delta is null)
        if (completion.usage != null) {
          lastResult = ChatResult<ChatMessage>(
            output: lastResult.output,
            messages: lastResult.messages,
            finishReason: mapFinishReason(
              completion.choices?.firstOrNull?.finishReason,
            ),
            metadata: {
              'created': completion.created,
              'model': completion.model,
              'system_fingerprint': completion.systemFingerprint,
            },
            usage: mapUsage(completion.usage),
            id: completion.id ?? lastResult.id,
          );
        }

        if (delta == null) continue;

        // Get the message with any text content (tool calls are only
        // accumulated)
        final message = messageFromOpenAIStreamDelta(
          delta,
          accumulatedToolCalls,
        );

        // Store the latest completion info for the final result
        lastResult = ChatResult<ChatMessage>(
          output: message,
          messages: [message],
          finishReason: mapFinishReason(
            completion.choices?.firstOrNull?.finishReason,
          ),
          metadata: {
            'created': completion.created,
            'model': completion.model,
            'system_fingerprint': completion.systemFingerprint,
          },
          usage: mapUsage(completion.usage),
          id: completion.id,
        );

        // If there's text content, stream it immediately
        if (message.parts.isNotEmpty) {
          // Accumulate text for the final message
          for (final part in message.parts) {
            if (part is TextPart) {
              accumulatedTextBuffer.write(part.text);
            }
          }

          // Yield the text-only message for streaming
          yield lastResult;
        }
      }

      // After streaming completes, yield final result with usage
      if (accumulatedToolCalls.isNotEmpty) {
        // Yield final message with tools
        final completeMessage = createCompleteMessageWithTools(
          accumulatedToolCalls,
          accumulatedText: accumulatedTextBuffer.toString(),
        );

        yield ChatResult<ChatMessage>(
          id: lastResult.id,
          output: completeMessage,
          messages: [completeMessage],
          finishReason: lastResult.finishReason,
          metadata: lastResult.metadata,
          usage: lastResult.usage,
        );
      } else {
        // Yield final result with empty output to provide usage without
        // duplicating text
        const emptyMessage = ChatMessage(
          role: ChatMessageRole.model,
          parts: [],
        );
        yield ChatResult<ChatMessage>(
          id: lastResult.id,
          output: emptyMessage,
          messages: const [],
          finishReason: lastResult.finishReason,
          metadata: lastResult.metadata,
          usage: lastResult.usage,
        );
      }

      _logger.info('OpenAI chat stream completed after $chunkCount chunks');
    } catch (e) {
      _logger.warning('OpenAI chat stream error: $e');
      rethrow;
    }
  }

  @override
  void dispose() => _client.endSession();
}
