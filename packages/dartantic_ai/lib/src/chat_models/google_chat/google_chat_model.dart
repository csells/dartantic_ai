import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as gai;
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../../agent/tool_constants.dart';
import '../../custom_http_client.dart';
import '../../providers/google_provider.dart';
import '../../retry_http_client.dart';
import 'google_chat_options.dart';
import 'google_message_mappers.dart';

/// Wrapper around [Google AI for Developers](https://ai.google.dev/) API
/// (aka Gemini API).
class GoogleChatModel extends ChatModel<GoogleChatModelOptions> {
  /// Creates a [GoogleChatModel] instance.
  GoogleChatModel({
    required super.name,
    required String apiKey,
    Uri? baseUrl,
    http.Client? client,
    List<Tool>? tools,
    super.temperature,
    super.defaultOptions = const GoogleChatModelOptions(),
  }) : _apiKey = apiKey,
       _httpClient = CustomHttpClient(
         baseHttpClient: client ?? RetryHttpClient(inner: http.Client()),
         baseUrl: baseUrl ?? GoogleProvider.defaultBaseUrl,
         headers: {'x-goog-api-key': apiKey},
         queryParams: const {},
       ),
       super(
         // Filter out return_result tool as Google has native typed output
         // support via responseMimeType: 'application/json'
         tools: tools?.where((t) => t.name != kReturnResultToolName).toList(),
       ) {
    _logger.info(
      'Creating Google model: $name '
      'with ${super.tools?.length ?? 0} tools, temp: $temperature',
    );

    _googleAiClient = _createGoogleAiClient();
  }

  /// Logger for Google chat model operations.
  static final Logger _logger = Logger('dartantic.chat.models.google');

  final String _apiKey;
  late gai.GenerativeModel _googleAiClient;
  String? _currentSystemInstruction;
  late final CustomHttpClient _httpClient;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    GoogleChatModelOptions? options,
    JsonSchema? outputSchema,
  }) {
    // Check if we have both tools and output schema
    if (outputSchema != null &&
        super.tools != null &&
        super.tools!.isNotEmpty) {
      throw ArgumentError(
        'Google Gemini does not support using tools and typed output '
        '(outputSchema) simultaneously. Either use tools without outputSchema, '
        'or use outputSchema without tools.',
      );
    }

    _logger.info(
      'Starting Google chat stream with ${messages.length} '
      'messages for model: $name',
    );
    final (
      model,
      prompt,
      safetySettings,
      generationConfig,
      tools,
      toolConfig,
    ) = _generateCompletionRequest(
      messages,
      options: options,
      outputSchema: outputSchema,
    );
    var chunkCount = 0;
    return _googleAiClient
        .generateContentStream(
          prompt,
          safetySettings: safetySettings,
          generationConfig: generationConfig,
          tools: tools,
          toolConfig: toolConfig,
        )
        .map((completion) {
          chunkCount++;
          _logger.fine('Received Google stream chunk $chunkCount');
          final result = completion.toChatResult(model);
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

  /// Creates a `GenerateContentRequest` from the given input.
  (
    String model,
    Iterable<gai.Content> prompt,
    List<gai.SafetySetting>? safetySettings,
    gai.GenerationConfig? generationConfig,
    List<gai.Tool>? tools,
    gai.ToolConfig? toolConfig,
  )
  _generateCompletionRequest(
    List<ChatMessage> messages, {
    GoogleChatModelOptions? options,
    JsonSchema? outputSchema,
  }) {
    _updateClientIfNeeded(messages, options);

    return (
      name,
      messages.toContentList(),
      (options?.safetySettings ?? defaultOptions.safetySettings)
          ?.toSafetySettings(),
      gai.GenerationConfig(
        candidateCount:
            options?.candidateCount ?? defaultOptions.candidateCount,
        stopSequences:
            options?.stopSequences ?? defaultOptions.stopSequences ?? const [],
        maxOutputTokens:
            options?.maxOutputTokens ?? defaultOptions.maxOutputTokens,
        temperature:
            temperature ?? options?.temperature ?? defaultOptions.temperature,
        topP: options?.topP ?? defaultOptions.topP,
        topK: options?.topK ?? defaultOptions.topK,
        responseMimeType: outputSchema != null
            ? 'application/json'
            : options?.responseMimeType ?? defaultOptions.responseMimeType,
        responseSchema:
            _createGoogleSchema(outputSchema) ??
            (options?.responseSchema ?? defaultOptions.responseSchema)
                ?.toSchema(),
      ),
      (tools ?? const []).toToolList(
        enableCodeExecution:
            options?.enableCodeExecution ??
            defaultOptions.enableCodeExecution ??
            false,
      ),
      null,
    );
  }

  @override
  void dispose() => _httpClient.close();

  /// Creates Google Schema from JsonSchema
  gai.Schema? _createGoogleSchema(JsonSchema? outputSchema) {
    if (outputSchema == null) return null;

    return _convertSchemaToGoogle(
      Map<String, dynamic>.from(outputSchema.schemaMap ?? {}),
    );
  }

  /// Converts a schema map to Google's Schema format
  gai.Schema _convertSchemaToGoogle(Map<String, dynamic> schemaMap) {
    var type = schemaMap['type'];
    final description = schemaMap['description'] as String?;
    var nullable = schemaMap['nullable'] as bool? ?? false;

    // Handle type arrays (e.g., ['string', 'null'])
    if (type is List) {
      final types = type;
      // If it contains 'null', mark as nullable
      if (types.contains('null')) {
        nullable = true;
        // Get the non-null type
        final nonNullTypes = types.where((t) => t != 'null').toList();
        if (nonNullTypes.length == 1) {
          type = nonNullTypes.first as String;
        } else if (nonNullTypes.isEmpty) {
          // Just null? Default to string
          type = 'string';
        } else {
          // Multiple non-null types, can't map semantically
          throw ArgumentError(
            'Cannot map type array $types to Google Schema; '
            'Google does not support union types.',
          );
        }
      } else {
        // Multiple types without null - can't map this
        throw ArgumentError(
          'Cannot map type array $types to Google Schema; '
          'Google does not support union types.',
        );
      }
    }

    // Check for unsupported schema constructs
    if (schemaMap.containsKey('anyOf') ||
        schemaMap.containsKey('oneOf') ||
        schemaMap.containsKey('allOf')) {
      throw ArgumentError(
        'Google Gemini does not support anyOf/oneOf/allOf schemas; '
        'consider using a string type and parsing the returned data, '
        'nullable types, optional properties, or a discriminated union '
        'pattern.',
      );
    }

    switch (type as String?) {
      case 'null':
        // Google doesn't have a specific null type, use nullable string
        return gai.Schema.string(description: description, nullable: true);
      case 'string':
        final enumValues = schemaMap['enum'] as List<dynamic>?;
        if (enumValues != null) {
          return gai.Schema.enumString(
            enumValues: enumValues.cast<String>(),
            description: description,
            nullable: nullable,
          );
        } else {
          return gai.Schema.string(
            description: description,
            nullable: nullable,
          );
        }
      case 'number':
        return gai.Schema.number(description: description, nullable: nullable);
      case 'integer':
        return gai.Schema.integer(description: description, nullable: nullable);
      case 'boolean':
        return gai.Schema.boolean(description: description, nullable: nullable);
      case 'array':
        final items = schemaMap['items'] as Map<String, dynamic>?;
        if (items == null) {
          throw ArgumentError(
            'Cannot map array without items to Google Schema; '
            'please specify the items type.',
          );
        }
        return gai.Schema.array(
          items: _convertSchemaToGoogle(Map<String, dynamic>.from(items)),
          description: description,
          nullable: nullable,
        );
      case 'object':
        final properties = schemaMap['properties'] as Map<String, dynamic>?;
        final convertedProperties = <String, gai.Schema>{};
        if (properties != null) {
          for (final entry in properties.entries) {
            convertedProperties[entry.key] = _convertSchemaToGoogle(
              Map<String, dynamic>.from(entry.value as Map<String, dynamic>),
            );
          }
        }

        final requiredFields = schemaMap['required'] as List<dynamic>?;
        return gai.Schema.object(
          properties: convertedProperties,
          description: description,
          nullable: nullable,
          requiredProperties: requiredFields?.cast<String>(),
        );
      default:
        throw ArgumentError(
          'Cannot map type "$type" to Google Schema; '
          'supported types are: string, number, integer, boolean, array, '
          'object.',
        );
    }
  }

  /// Create a new [gai.GenerativeModel] instance.
  gai.GenerativeModel _createGoogleAiClient({String? systemInstruction}) =>
      gai.GenerativeModel(
        model: name,
        apiKey: _apiKey,
        httpClient: _httpClient,
        systemInstruction: systemInstruction != null
            ? gai.Content.system(systemInstruction)
            : null,
      );

  /// Updates the model in [_googleAiClient] if needed.
  void _updateClientIfNeeded(
    List<ChatMessage> messages,
    GoogleChatModelOptions? options,
  ) {
    final systemInstruction =
        messages.firstOrNull?.role == ChatMessageRole.system
        ? messages.firstOrNull?.parts
              .whereType<TextPart>()
              .map((p) => p.text)
              .join('\n')
        : null;

    if (systemInstruction != _currentSystemInstruction) {
      _currentSystemInstruction = systemInstruction;
      _googleAiClient = _createGoogleAiClient(
        systemInstruction: systemInstruction,
      );
    }
  }
}
