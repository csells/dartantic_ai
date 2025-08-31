import 'dart:async';
import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:ollama_dart/ollama_dart.dart'
    show GenerateChatCompletionResponse, OllamaClient;

import '../../agent/tool_constants.dart';
import '../../providers/ollama_provider.dart';
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
  }) : _client = OllamaClient(baseUrl: baseUrl?.toString(), client: client),
       _baseUrl = baseUrl,
       super(
         name: name,
         defaultOptions: defaultOptions ?? const OllamaChatOptions(),
         // Filter out return_result tool as Ollama has native typed output
         // support via format: 'json'
         tools: tools?.where((t) => t.name != kReturnResultToolName).toList(),
       ) {
    _logger.info(
      'Creating Ollama model: $name '
      'with ${tools?.length ?? 0} tools, temp: $temperature',
    );
  }

  static final Logger _logger = Logger('dartantic.chat.models.ollama');

  final OllamaClient _client;
  final Uri? _baseUrl;

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

    // If we have an output schema, we need to use direct HTTP because
    // ollama_dart doesn't support dynamic format objects, only the
    // ResponseFormat enum
    if (outputSchema != null) {
      return _sendStreamWithSchema(
        messages,
        outputSchema: outputSchema,
        options: options,
      );
    }

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

  /// WORKAROUND: Direct HTTP implementation for JSON schema support
  ///
  /// The ollama_dart package currently only supports ResponseFormat enum (just
  /// "json") but the Ollama API itself supports full JSON schema objects in the
  /// format field. This method bypasses the package limitation by making direct
  /// HTTP requests.
  ///
  /// TODO: Remove this workaround once ollama_dart supports dynamic format
  /// objects GitHub issue:
  /// https://github.com/davidmigloz/langchain_dart/issues/740
  Stream<ChatResult<ChatMessage>> _sendStreamWithSchema(
    List<ChatMessage> messages, {
    required JsonSchema outputSchema,
    OllamaChatOptions? options,
  }) async* {
    _logger.info('Using direct HTTP for Ollama with JSON schema (workaround)');

    // Create base request
    final request = ollama_mappers.generateChatCompletionRequest(
      messages,
      modelName: name,
      options: options,
      defaultOptions: defaultOptions,
      tools: tools,
      temperature: temperature,
      outputSchema: null, // Don't pass schema here, we'll add it manually
    );

    // Convert to JSON and add the schema as format
    final requestJson = request.toJson();
    requestJson['format'] = outputSchema.schemaMap;

    // Make direct HTTP request
    final httpClient = http.Client();
    try {
      final resolvedBaseUrl = _baseUrl ?? OllamaProvider.defaultBaseUrl;
      final response = await httpClient.post(
        resolvedBaseUrl.replace(path: '${resolvedBaseUrl.path}/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestJson),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Ollama API error: ${response.statusCode} ${response.body}',
        );
      }

      // Parse streaming response
      var chunkCount = 0;
      final lines = response.body.split('\n');
      for (final line in lines) {
        if (line.trim().isEmpty) continue;

        final json = jsonDecode(line);
        final ollamaResponse = GenerateChatCompletionResponse.fromJson(json);
        chunkCount++;
        _logger.fine('Received Ollama schema stream chunk $chunkCount');

        final result = ollama_mappers.ChatResultMapper(
          ollamaResponse,
        ).toChatResult();
        yield ChatResult<ChatMessage>(
          output: result.output,
          messages: result.messages,
          finishReason: result.finishReason,
          metadata: result.metadata,
          usage: result.usage,
          id: result.id,
        );
      }
    } finally {
      httpClient.close();
    }
  }

  @override
  void dispose() => _client.endSession();
}
