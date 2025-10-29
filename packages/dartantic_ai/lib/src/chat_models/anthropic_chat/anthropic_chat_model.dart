import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as a;
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import 'anthropic_chat_options.dart';
import 'anthropic_message_mappers.dart';

/// Wrapper around [Anthropic Messages
/// API](https://docs.anthropic.com/en/api/messages) (aka Claude API).
class AnthropicChatModel extends ChatModel<AnthropicChatOptions> {
  /// Creates a [AnthropicChatModel] instance.
  AnthropicChatModel({
    required super.name,
    required String apiKey,
    Uri? baseUrl,
    super.tools,
    super.temperature,
    http.Client? client,
    AnthropicChatOptions? defaultOptions,
  }) : _client = a.AnthropicClient(
         apiKey: apiKey,
         baseUrl: baseUrl?.toString(),
         client: client,
       ),
       super(defaultOptions: defaultOptions ?? const AnthropicChatOptions()) {
    _logger.info(
      'Creating Anthropic model: $name with '
      '${tools?.length ?? 0} tools, temp: $temperature',
    );
  }

  /// Logger for Anthropic chat model operations.
  static final Logger _logger = Logger('dartantic.chat.models.anthropic');

  final a.AnthropicClient _client;

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

    var chunkCount = 0;
    await for (final result
        in _client
            .createMessageStream(
              request: createMessageRequest(
                messages,
                modelName: name,
                tools: tools,
                temperature: temperature,
                options: options,
                defaultOptions: defaultOptions,
                outputSchema: outputSchema,
              ),
            )
            .handleError((Object e, StackTrace st) {
              // Handle unknown event types gracefully (e.g., signature_delta)
              // These are new Anthropic API features not yet in the SDK
              if (e.toString().contains('Invalid union type')) {
                _logger.fine('Skipping unknown Anthropic event type: $e');
                // Don't rethrow - just skip this event
                return;
              }
              // Rethrow all other errors
              Error.throwWithStackTrace(e, st);
            })
            .transform(MessageStreamEventTransformer())) {
      chunkCount++;
      _logger.fine('Received Anthropic stream chunk $chunkCount');
      // Filter system messages from the response
      yield ChatResult<ChatMessage>(
        id: result.id,
        output: result.output,
        messages: result.messages,
        finishReason: result.finishReason,
        metadata: result.metadata,
        usage: result.usage,
      );
    }
  }

  @override
  void dispose() => _client.endSession();
}
