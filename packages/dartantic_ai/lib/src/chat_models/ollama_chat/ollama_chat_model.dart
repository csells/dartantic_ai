import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:ollama_dart/ollama_dart.dart' show OllamaClient;

import 'ollama_chat_options.dart';
import 'ollama_message_mappers.dart' as ollama_mappers;

export 'ollama_chat_options.dart';

/// Wrapper around [Ollama](https://ollama.ai) Chat API that enables to interact
/// with the LLMs in a chat-like fashion.
class OllamaChatModel extends ChatModel<OllamaChatOptions> {
  /// Creates a [OllamaChatModel] instance.
  OllamaChatModel({
    required String name,
    List<Tool>? tools,
    super.temperature,
    OllamaChatOptions? defaultOptions,
    Uri? baseUrl,
    http.Client? client,
    Map<String, String>? headers,
  }) : _client = OllamaClient(
         baseUrl: baseUrl?.toString(),
         client: client,
         headers: headers,
       ),
       super(
         name: name,
         defaultOptions: defaultOptions ?? const OllamaChatOptions(),
         tools: tools,
       ) {
    _logger.info(
      'Creating Ollama model: $name '
      'with ${tools?.length ?? 0} tools, temp: $temperature',
    );
  }

  static final Logger _logger = Logger('dartantic.chat.models.ollama');

  final OllamaClient _client;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    OllamaChatOptions? options,
    JsonSchema? outputSchema,
  }) {
    // Check if we have both tools and output schema
    if (outputSchema != null &&
        super.tools != null &&
        super.tools!.isNotEmpty) {
      throw ArgumentError(
        'Ollama does not support using tools and typed output '
        '(outputSchema) simultaneously. Either use tools without outputSchema, '
        'or use outputSchema without tools.',
      );
    }

    _logger.info(
      'Starting Ollama chat stream with ${messages.length} '
      'messages for model: $name',
    );
    var chunkCount = 0;

    return _client
        .generateChatCompletionStream(
          request: ollama_mappers.generateChatCompletionRequest(
            messages,
            modelName: name,
            options: options,
            defaultOptions: defaultOptions,
            tools: tools,
            temperature: temperature,
            outputSchema: outputSchema,
          ),
        )
        .map((completion) {
          chunkCount++;
          _logger.fine('Received Ollama stream chunk $chunkCount');
          final result = ollama_mappers.ChatResultMapper(
            completion,
          ).toChatResult();
          return ChatResult<ChatMessage>(
            output: result.output,
            messages: result.messages,
            finishReason: result.finishReason,
            metadata: result.metadata,
            usage: result.usage,
            id: result.id,
          );
        });
  }

  @override
  void dispose() => _client.endSession();
}
