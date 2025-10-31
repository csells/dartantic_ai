import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:mistralai_dart/mistralai_dart.dart';

import 'mistral_chat_options.dart';
import 'mistral_message_mappers.dart';

/// Wrapper around [Mistral AI](https://docs.mistral.ai) Chat Completions API.
class MistralChatModel extends ChatModel<MistralChatModelOptions> {
  /// Creates a [MistralChatModel] instance.
  MistralChatModel({
    required String name,
    required String apiKey,
    super.tools,
    super.temperature,
    MistralChatModelOptions? defaultOptions,
    Uri? baseUrl,
    http.Client? client,
  }) : _client = MistralAIClient(
         apiKey: apiKey,
         baseUrl: baseUrl?.toString(),
         client: client,
       ),
       super(
         name: name,
         defaultOptions: defaultOptions ?? const MistralChatModelOptions(),
       ) {
    _logger.info(
      'Creating Mistral model: $name '
      'with ${tools?.length ?? 0} tools, temp: $temperature',
    );

    if (tools != null) {
      // TODO: Mistral doesn't support tools yet, waiting for a fix:
      // https://github.com/davidmigloz/langchain_dart/issues/653
      throw Exception('Tools are not supported by Mistral.');
    }
  }

  static final Logger _logger = Logger('dartantic.chat.models.mistral');

  final MistralAIClient _client;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    MistralChatModelOptions? options,
    JsonSchema? outputSchema,
  }) {
    _logger.info(
      'Starting Mistral chat stream with ${messages.length} messages for '
      'model: $name',
    );
    var chunkCount = 0;

    if (outputSchema != null) {
      throw Exception(
        'JSON schema support is not yet implemented for Mistral.',
      );
    }

    final request = createChatCompletionRequest(
      messages,
      modelName: name,
      tools: tools,
      temperature: temperature,
      options: options,
      defaultOptions: defaultOptions,
    );

    return _client.createChatCompletionStream(request: request).map((
      completion,
    ) {
      chunkCount++;
      _logger.fine('Received Mistral stream chunk $chunkCount');
      final result = completion.toChatResult();
      return ChatResult<ChatMessage>(
        id: result.id,
        output: result.output,
        messages: result.messages,
        finishReason: result.finishReason,
        metadata: result.metadata,
        usage: result.usage,
      );
    });
  }

  /// Creates a GenerateCompletionRequest from the given input.
  ChatCompletionRequest createChatCompletionRequest(
    List<ChatMessage> messages, {
    required String modelName,
    required MistralChatModelOptions defaultOptions,
    List<Tool>? tools,
    double? temperature,
    MistralChatModelOptions? options,
  }) => ChatCompletionRequest(
    model: ChatCompletionModel.modelId(modelName),
    messages: messages.toChatCompletionMessages(),
    temperature: temperature,
    topP: options?.topP ?? defaultOptions.topP,
    maxTokens: options?.maxTokens ?? defaultOptions.maxTokens,
    safePrompt: options?.safePrompt ?? defaultOptions.safePrompt,
    randomSeed: options?.randomSeed ?? defaultOptions.randomSeed,
    stream: true,
  );

  @override
  void dispose() => _client.endSession();
}
