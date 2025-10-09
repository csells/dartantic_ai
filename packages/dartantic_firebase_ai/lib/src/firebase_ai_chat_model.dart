import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:firebase_ai/firebase_ai.dart' as fai;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import 'firebase_ai_chat_options.dart';
import 'firebase_message_mappers.dart';

/// Wrapper around Firebase AI (Gemini via Firebase).
class FirebaseAIChatModel extends ChatModel<FirebaseAIChatModelOptions> {
  /// Creates a [FirebaseAIChatModel] instance.
  FirebaseAIChatModel({
    required super.name,
    List<Tool>? tools,
    super.temperature,
    super.defaultOptions = const FirebaseAIChatModelOptions(),
  }) : super(
         // Filter out return_result tool as Firebase AI has native typed
         // output support via responseMimeType: 'application/json'
         tools: tools?.where((t) => t.name != kReturnResultToolName).toList(),
       ) {
    _logger.info(
      'Creating Firebase AI model: $name '
      'with ${super.tools?.length ?? 0} tools, temp: $temperature',
    );

    _firebaseAiClient = _createFirebaseAiClient();
  }

  /// Logger for Firebase AI chat model operations.
  static final Logger _logger = Logger('dartantic.chat.models.firebase_ai');

  /// The name of the return_result tool that should be filtered out.
  static const String kReturnResultToolName = 'return_result';

  late fai.GenerativeModel _firebaseAiClient;
  String? _currentSystemInstruction;

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    FirebaseAIChatModelOptions? options,
    JsonSchema? outputSchema,
  }) {
    // Check if we have both tools and output schema
    if (outputSchema != null &&
        super.tools != null &&
        super.tools!.isNotEmpty) {
      throw ArgumentError(
        'Firebase AI does not support using tools and typed output '
        '(outputSchema) simultaneously. Either use tools without outputSchema, '
        'or use outputSchema without tools.',
      );
    }

    _logger.info(
      'Starting Firebase AI chat stream with ${messages.length} '
      'messages for model: $name',
    );

    final (
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
    return _firebaseAiClient
        .generateContentStream(
          prompt,
          safetySettings: safetySettings,
          generationConfig: generationConfig,
          tools: tools,
          toolConfig: toolConfig,
        )
        .handleError((error, stackTrace) {
          _logger.severe(
            'Firebase AI stream error: ${error.runtimeType}: $error',
            error,
            stackTrace,
          );
          
          // Re-throw with more context for common Firebase AI errors
          if (error.toString().contains('quota')) {
            throw Exception(
              'Firebase AI quota exceeded. Please check your Firebase project '
              'quotas and billing settings. Original error: $error',
            );
          } else if (error.toString().contains('safety')) {
            throw Exception(
              'Firebase AI safety filter triggered. The content may violate '
              'safety guidelines. Original error: $error',
            );
          } else if (error.toString().contains('permission')) {
            throw Exception(
              'Firebase AI permission denied. Ensure your Firebase project '
              'has AI services enabled and proper authentication. '
              'Original error: $error',
            );
          }
          
          // Re-throw original error if no specific handling
          throw error;
        })
        .map((completion) {
          chunkCount++;
          _logger.fine('Received Firebase AI stream chunk $chunkCount');
          
          try {
            final result = completion.toChatResult(name);
            return ChatResult<ChatMessage>(
              id: result.id,
              output: result.output,
              messages: result.messages,
              finishReason: result.finishReason,
              metadata: result.metadata,
              usage: result.usage,
            );
          } catch (e, stackTrace) {
            _logger.severe(
              'Error processing Firebase AI response chunk $chunkCount: $e',
              e,
              stackTrace,
            );
            rethrow;
          }
        });
  }

  /// Creates a completion request from the given input.
  (
    Iterable<fai.Content> prompt,
    List<fai.SafetySetting>? safetySettings,
    fai.GenerationConfig? generationConfig,
    List<fai.Tool>? tools,
    fai.ToolConfig? toolConfig,
  )
  _generateCompletionRequest(
    List<ChatMessage> messages, {
    FirebaseAIChatModelOptions? options,
    JsonSchema? outputSchema,
  }) {
    _updateClientIfNeeded(messages, options);

    return (
      messages.toContentList(),
      (options?.safetySettings ?? defaultOptions.safetySettings)
          ?.toSafetySettings(),
      fai.GenerationConfig(
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
            _createFirebaseSchema(outputSchema) ??
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
  void dispose() {}

  /// Creates Firebase Schema from JsonSchema
  fai.Schema? _createFirebaseSchema(JsonSchema? outputSchema) {
    if (outputSchema == null) return null;

    return _convertSchemaToFirebase(
      Map<String, dynamic>.from(outputSchema.schemaMap ?? {}),
    );
  }

  /// Converts a schema map to Firebase's Schema format
  fai.Schema _convertSchemaToFirebase(Map<String, dynamic> schemaMap) {
    var type = schemaMap['type'];
    final description = schemaMap['description'] as String?;
    var nullable = schemaMap['nullable'] as bool? ?? false;

    // Handle type arrays (e.g., ['string', 'null'])
    if (type is List) {
      final types = type;
      if (types.contains('null')) {
        nullable = true;
        final nonNullTypes = types.where((t) => t != 'null').toList();
        if (nonNullTypes.length == 1) {
          type = nonNullTypes.first as String;
        } else if (nonNullTypes.isEmpty) {
          type = 'string';
        } else {
          throw ArgumentError(
            'Cannot map type array $types to Firebase Schema; '
            'Firebase does not support union types.',
          );
        }
      } else {
        throw ArgumentError(
          'Cannot map type array $types to Firebase Schema; '
          'Firebase does not support union types.',
        );
      }
    }

    // Check for unsupported schema constructs
    if (schemaMap.containsKey('anyOf') ||
        schemaMap.containsKey('oneOf') ||
        schemaMap.containsKey('allOf')) {
      throw ArgumentError(
        'Firebase AI does not support anyOf/oneOf/allOf schemas; '
        'consider using a string type and parsing the returned data, '
        'nullable types, optional properties, or a discriminated union '
        'pattern.',
      );
    }

    switch (type as String?) {
      case 'null':
        return fai.Schema.string(description: description, nullable: true);
      case 'string':
        final enumValues = schemaMap['enum'] as List<dynamic>?;
        if (enumValues != null) {
          return fai.Schema.enumString(
            enumValues: enumValues.cast<String>(),
            description: description,
            nullable: nullable,
          );
        } else {
          return fai.Schema.string(
            description: description,
            nullable: nullable,
          );
        }
      case 'number':
        return fai.Schema.number(description: description, nullable: nullable);
      case 'integer':
        return fai.Schema.integer(description: description, nullable: nullable);
      case 'boolean':
        return fai.Schema.boolean(description: description, nullable: nullable);
      case 'array':
        final items = schemaMap['items'] as Map<String, dynamic>?;
        if (items == null) {
          throw ArgumentError(
            'Cannot map array without items to Firebase Schema; '
            'please specify the items type.',
          );
        }
        return fai.Schema.array(
          items: _convertSchemaToFirebase(Map<String, dynamic>.from(items)),
          description: description,
          nullable: nullable,
        );
      case 'object':
        final properties = schemaMap['properties'] as Map<String, dynamic>?;
        final convertedProperties = <String, fai.Schema>{};
        if (properties != null) {
          for (final entry in properties.entries) {
            convertedProperties[entry.key] = _convertSchemaToFirebase(
              Map<String, dynamic>.from(entry.value as Map<String, dynamic>),
            );
          }
        }

        return fai.Schema.object(
          properties: convertedProperties,
          description: description,
          nullable: nullable,
        );
      default:
        throw ArgumentError(
          'Cannot map type "$type" to Firebase Schema; '
          'supported types are: string, number, integer, boolean, array, '
          'object.',
        );
    }
  }

  /// Create a new [fai.GenerativeModel] instance.
  fai.GenerativeModel _createFirebaseAiClient({String? systemInstruction}) {
    try {
      _logger.fine('Creating Firebase AI client for model: $name');
      
      return fai.FirebaseAI.googleAI().generativeModel(
        model: name,
        systemInstruction: systemInstruction != null
            ? fai.Content.system(systemInstruction)
            : null,
      );
    } catch (e, stackTrace) {
      _logger.severe(
        'Failed to create Firebase AI client for model $name: $e',
        e,
        stackTrace,
      );
      
      // Provide helpful error messages for common issues
      if (e.toString().contains('Firebase')) {
        throw Exception(
          'Failed to initialize Firebase AI. Ensure Firebase is properly '
          'configured in your app and AI services are enabled in your '
          'Firebase project. Original error: $e',
        );
      } else if (e.toString().contains('model')) {
        throw ArgumentError(
          'Unsupported Firebase AI model: $name. Please check the model '
          "name and ensure it's available in your Firebase project. "
          'Original error: $e',
        );
      }
      
      rethrow;
    }
  }

  /// Updates the model if needed.
  void _updateClientIfNeeded(
    List<ChatMessage> messages,
    FirebaseAIChatModelOptions? options,
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
      _firebaseAiClient = _createFirebaseAiClient(
        systemInstruction: systemInstruction,
      );
    }
  }
}
