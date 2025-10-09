import 'dart:convert';

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
       _apiKey = apiKey,
       _baseUrl = baseUrl?.toString() ?? 'https://api.mistral.ai/v1',
       _httpClient = client,
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
  final String _apiKey;
  final String _baseUrl;
  final http.Client? _httpClient;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    MistralChatModelOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    _logger.info(
      'Starting Mistral chat stream with ${messages.length} messages for '
      'model: $name',
    );
    var chunkCount = 0;
    LanguageModelUsage? finalUsage;

    if (outputSchema != null) {
      throw Exception(
        'JSON schema support is not yet implemented for Mistral.',
      );
    }

    // WORKAROUND: Direct HTTP implementation to extract usage from stream
    //
    // The mistralai_dart package's ChatCompletionStreamResponse schema doesn't
    // include the 'usage' field, but the Mistral API does return it in the
    // final streaming chunk. We make a direct HTTP request to parse the usage
    // from raw JSON before deserializing into ChatCompletionStreamResponse.
    //
    // TODO: Remove this workaround once mistralai_dart adds usage field
    // https://github.com/davidmigloz/langchain_dart/issues/781
    final request = createChatCompletionRequest(
      messages,
      modelName: name,
      tools: tools,
      temperature: temperature,
      options: options,
      defaultOptions: defaultOptions,
    );

    // Use the provided HTTP client or create a new one
    final httpClient = _httpClient ?? http.Client();
    final shouldCloseClient = _httpClient == null;

    try {
      final response = await httpClient.send(
        http.Request('POST', Uri.parse('$_baseUrl/chat/completions'))
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
          })
          ..body = jsonEncode(request.copyWith(stream: true).toJson()),
      );

      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw Exception('Mistral API error: ${response.statusCode} $body');
      }

      // Parse the SSE stream
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .where((i) => i.startsWith('data: ') && !i.endsWith('[DONE]'))
              .map((item) => item.substring(6))) {
        chunkCount++;
        _logger.fine('Received Mistral stream chunk $chunkCount');

        final json = jsonDecode(line) as Map<String, dynamic>;

        // Extract usage if present (Mistral sends this in the final chunk)
        if (json.containsKey('usage')) {
          final usageJson = json['usage'] as Map<String, dynamic>;
          finalUsage = LanguageModelUsage(
            promptTokens: usageJson['prompt_tokens'] as int?,
            responseTokens: usageJson['completion_tokens'] as int?,
            totalTokens: usageJson['total_tokens'] as int?,
          );
          _logger.fine(
            'Captured Mistral usage: ${finalUsage.promptTokens}/${finalUsage.responseTokens}/${finalUsage.totalTokens}',
          );
        }

        // Parse the completion normally
        final completion = ChatCompletionStreamResponse.fromJson(json);
        final result = completion.toChatResult();

        // Add usage to the result if we have it
        yield ChatResult<ChatMessage>(
          id: result.id,
          output: result.output,
          messages: result.messages,
          finishReason: result.finishReason,
          metadata: result.metadata,
          usage: finalUsage,
        );
      }
    } finally {
      if (shouldCloseClient) {
        httpClient.close();
      }
    }
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
