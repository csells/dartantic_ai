import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:firebase_ai/firebase_ai.dart' as f;
import 'package:logging/logging.dart';

import 'firebase_ai_chat_options.dart';
import 'firebase_ai_thinking_utils.dart';

/// Logger for Firebase message mapping operations.
final Logger _logger = Logger('dartantic.chat.mappers.firebase_ai');

/// Extension on [List<Message>] to convert messages to Firebase AI content.
extension MessageListMapper on List<ChatMessage> {
  /// Converts this list of [ChatMessage]s to a list of [f.Content]s.
  ///
  /// Groups consecutive tool result messages into a single
  /// f.Content.functionResponses() as required by Firebase AI's API.
  List<f.Content> toContentList() {
    final nonSystemMessages = where(
      (message) => message.role != ChatMessageRole.system,
    ).toList();
    _logger.fine(
      'Converting ${nonSystemMessages.length} non-system messages to Firebase '
      'format',
    );
    final result = <f.Content>[];

    for (var i = 0; i < nonSystemMessages.length; i++) {
      final message = nonSystemMessages[i];

      // Check if this is a tool result message
      final hasToolResults = message.parts.whereType<ToolPart>().any(
        (p) => p.result != null,
      );

      if (hasToolResults) {
        // Collect all consecutive tool result messages
        final toolMessages = [message];
        var j = i + 1;
        _logger.fine(
          'Found tool result message at index $i, collecting consecutive tool '
          'messages',
        );
        while (j < nonSystemMessages.length) {
          final nextMsg = nonSystemMessages[j];
          final nextHasToolResults = nextMsg.parts.whereType<ToolPart>().any(
            (p) => p.result != null,
          );
          if (nextHasToolResults) {
            toolMessages.add(nextMsg);
            j++;
          } else {
            break;
          }
        }

        // Create a single f.Content.functionResponses with all tool responses
        _logger.fine(
          'Creating function responses for ${toolMessages.length} tool '
          'messages',
        );
        result.add(_mapToolResultMessages(toolMessages));

        // Skip the processed messages
        i = j - 1;
      } else {
        // Handle non-tool messages normally
        result.add(_mapMessage(message));
      }
    }

    return result;
  }

  f.Content _mapMessage(ChatMessage message) {
    switch (message.role) {
      case ChatMessageRole.system:
        throw AssertionError('System messages should be filtered out');
      case ChatMessageRole.user:
        return _mapUserMessage(message);
      case ChatMessageRole.model:
        return _mapModelMessage(message);
    }
  }

  f.Content _mapUserMessage(ChatMessage message) {
    final contentParts = <f.Part>[];
    _logger.fine('Mapping user message with ${message.parts.length} parts');

    for (final part in message.parts) {
      switch (part) {
        case TextPart(:final text):
          contentParts.add(f.TextPart(text));
        case DataPart(:final bytes, :final mimeType):
          contentParts.add(f.InlineDataPart(mimeType, bytes));
        case LinkPart(:final url):
          // Note: FilePart API may have changed in v3.3.0 - 
          // using TextPart as fallback
          contentParts.add(f.TextPart('Link: $url'));
        case ToolPart():
          // Tool parts in user messages are handled separately as tool results
          break;
        default:
          // Handle any other part types we don't recognize
          _logger.fine('Skipping unrecognized part type: ${part.runtimeType}');
      }
    }

    return f.Content.multi(contentParts);
  }

  f.Content _mapModelMessage(ChatMessage message) {
    final contentParts = <f.Part>[];

    // Add text parts
    final textParts = message.parts.whereType<TextPart>();
    _logger.fine('Mapping model message with ${message.parts.length} parts');
    for (final part in textParts) {
      if (part.text.isNotEmpty) {
        contentParts.add(f.TextPart(part.text));
      }
    }

    // Add tool calls
    final toolParts = message.parts.whereType<ToolPart>();
    var toolCallCount = 0;
    for (final part in toolParts) {
      if (part.kind == ToolPartKind.call) {
        // This is a tool call, not a result
        contentParts.add(f.FunctionCall(part.name, part.arguments ?? {}));
        toolCallCount++;
      }
    }
    _logger.fine('Added $toolCallCount tool calls to model message');

    return f.Content.model(contentParts);
  }

  /// Maps multiple tool result messages to a single
  /// f.Content.functionResponses.
  /// This is required by Firebase AI's API - all function responses must be
  /// grouped together
  f.Content _mapToolResultMessages(List<ChatMessage> messages) {
    final functionResponses = <f.FunctionResponse>[];
    _logger.fine(
      'Mapping ${messages.length} tool result messages to Firebase function '
      'responses',
    );

    for (final message in messages) {
      for (final part in message.parts) {
        if (part is ToolPart && part.kind == ToolPartKind.result) {
          // Firebase's FunctionResponse requires a Map<String, Object?>
          // If the result is already a Map, use it directly
          // Otherwise, wrap it in a Map with a "result" key
          final response = part.result is Map<String, Object?>
              ? part.result as Map<String, Object?>
              : <String, Object?>{'result': part.result};

          // Extract the original function name from our generated ID
          final functionName = _extractToolNameFromId(part.id) ?? part.name;
          _logger.fine('Creating function response for tool: $functionName');

          functionResponses.add(f.FunctionResponse(functionName, response));
        }
      }
    }

    return f.Content.functionResponses(functionResponses);
  }

  /// Extracts the tool name from a generated tool call ID.
  String? _extractToolNameFromId(String? id) {
    if (id == null) return null;
    // Tool IDs are typically in format: toolName_hash
    final parts = id.split('_');
    return parts.isNotEmpty ? parts.first : null;
  }
}

/// Extension on [f.GenerateContentResponse] to convert to [ChatResult].
extension GenerateContentResponseMapper on f.GenerateContentResponse {
  /// Converts this [f.GenerateContentResponse] to a [ChatResult].
  ChatResult<ChatMessage> toChatResult(String model) {
    final candidate = candidates.first;
    final parts = <Part>[];
    _logger.fine('Converting Firebase response to ChatResult: model=$model');

    // Process all parts from the response
    _logger.fine(
      'Processing ${candidate.content.parts.length} parts from Firebase '
      'response',
    );
    for (final part in candidate.content.parts) {
      switch (part) {
        case f.TextPart(:final text):
          if (text.isNotEmpty) {
            parts.add(TextPart(text));
          }
        case f.InlineDataPart(:final mimeType, :final bytes):
          parts.add(DataPart(bytes, mimeType: mimeType));
        case f.FunctionCall(:final name, :final args):
          _logger.fine('Processing function call: $name');
          // Generate a unique ID for this tool call
          final toolId = _generateToolCallId(
            toolName: name,
            providerHint: 'firebase',
            arguments: args,
          );
          parts.add(ToolPart.call(id: toolId, name: name, arguments: args));
        case f.FunctionResponse():
          // Function responses shouldn't appear in model output
          break;
        case f.UnknownPart():
          // Skip unknown parts
          _logger.fine('Skipping unknown part type');
        default:
          // Handle any other Firebase part types we don't recognize
          _logger.fine(
            'Skipping unrecognized Firebase part type: ${part.runtimeType}',
          );
      }
    }

    final message = ChatMessage(role: ChatMessageRole.model, parts: parts);

    // Create initial ChatResult
    final result = ChatResult<ChatMessage>(
      output: message,
      messages: [message],
      finishReason: _mapFinishReason(candidate.finishReason),
      metadata: <String, Object?>{
        'model': model,
        'block_reason': promptFeedback?.blockReason?.name,
        'block_reason_message': promptFeedback?.blockReasonMessage,
        'safety_ratings': candidate.safetyRatings
            ?.map(
              (r) => <String, Object?>{
                'category': r.category.name,
                'probability': r.probability.name,
              },
            )
            .toList(growable: false),
        'citation_metadata': candidate.citationMetadata?.toString(),
        'finish_message': candidate.finishMessage,
      },
      usage: LanguageModelUsage(
        promptTokens: usageMetadata?.promptTokenCount,
        responseTokens: usageMetadata?.candidatesTokenCount,
        totalTokens: usageMetadata?.totalTokenCount,
      ),
    );

    // Extract thinking metadata and add to result metadata
    final thinkingContent = FirebaseAIThinkingUtils.extractThinking(
      result,
      options: const FirebaseAIThinkingOptions(enabled: true),
    );
    
    if (thinkingContent != null && thinkingContent.isNotEmpty) {
      result.metadata['thinking'] = thinkingContent;
      _logger.fine('Added thinking metadata: ${thinkingContent.length} chars');
    }

    return result;
  }

  FinishReason _mapFinishReason(f.FinishReason? reason) => switch (reason) {
    f.FinishReason.stop => FinishReason.stop,
    f.FinishReason.maxTokens => FinishReason.length,
    f.FinishReason.safety => FinishReason.contentFilter,
    f.FinishReason.recitation => FinishReason.recitation,
    f.FinishReason.other => FinishReason.unspecified,
    f.FinishReason.unknown => FinishReason.unspecified,
    null => FinishReason.unspecified,
  };

  /// Generates a unique ID for a tool call.
  String _generateToolCallId({
    required String toolName,
    required String providerHint,
    required Map<String, Object?> arguments,
  }) {
    // Simple implementation: toolName_hashCode
    final hash = Object.hash(toolName, providerHint, arguments);
    return '${toolName}_${hash.abs()}';
  }
}

/// Extension on [List<FirebaseAISafetySetting>] to convert to Firebase SDK
/// safety settings.
extension SafetySettingsMapper on List<FirebaseAISafetySetting> {
  /// Converts this list of [FirebaseAISafetySetting]s to a list of
  /// [f.SafetySetting]s.
  List<f.SafetySetting> toSafetySettings() {
    _logger.fine('Converting $length safety settings to Firebase format');
    return map(
      (setting) => f.SafetySetting(
        switch (setting.category) {
          FirebaseAISafetySettingCategory.unspecified =>
            f
                .HarmCategory
                .harassment, // Use a default since unspecified is removed
          FirebaseAISafetySettingCategory.harassment =>
            f.HarmCategory.harassment,
          FirebaseAISafetySettingCategory.hateSpeech =>
            f.HarmCategory.hateSpeech,
          FirebaseAISafetySettingCategory.sexuallyExplicit =>
            f.HarmCategory.sexuallyExplicit,
          FirebaseAISafetySettingCategory.dangerousContent =>
            f.HarmCategory.dangerousContent,
        },
        switch (setting.threshold) {
          FirebaseAISafetySettingThreshold.unspecified =>
            f
                .HarmBlockThreshold
                .none, // Use a default since unspecified is removed
          FirebaseAISafetySettingThreshold.blockLowAndAbove =>
            f.HarmBlockThreshold.low,
          FirebaseAISafetySettingThreshold.blockMediumAndAbove =>
            f.HarmBlockThreshold.medium,
          FirebaseAISafetySettingThreshold.blockOnlyHigh =>
            f.HarmBlockThreshold.high,
          FirebaseAISafetySettingThreshold.blockNone =>
            f.HarmBlockThreshold.none,
        },
        null, // Third parameter seems to be needed but null works as default
      ),
    ).toList(growable: false);
  }
}

/// Extension on [List<Tool>?] to convert to Firebase SDK tool list.
extension ChatToolListMapper on List<Tool>? {
  /// Converts this list of [Tool]s to a list of [f.Tool]s, optionally
  /// enabling code execution.
  List<f.Tool>? toToolList({required bool enableCodeExecution}) {
    final hasTools = this != null && this!.isNotEmpty;
    _logger.fine(
      'Converting tools to Firebase format: hasTools=$hasTools, '
      'enableCodeExecution=$enableCodeExecution, '
      'toolCount=${this?.length ?? 0}',
    );
    if (!hasTools && !enableCodeExecution) {
      return null;
    }
    final functionDeclarations = hasTools
        ? this!
              .map(
                (tool) => f.FunctionDeclaration(
                  tool.name,
                  tool.description,
                  parameters: <String, f.Schema>{
                    'properties': Map<String, dynamic>.from(
                      tool.inputSchema.schemaMap ?? <String, dynamic>{},
                    ).toSchema(),
                  },
                ),
              )
              .toList(growable: false)
        : null;
    final codeExecution = enableCodeExecution ? const f.CodeExecution() : null;
    if ((functionDeclarations == null || functionDeclarations.isEmpty) &&
        codeExecution == null) {
      return null;
    }
    return <f.Tool>[f.Tool.functionDeclarations(functionDeclarations ?? [])];
  }
}

/// Extension on [Map<String, dynamic>] to convert to Firebase SDK schema.
extension SchemaMapper on Map<String, dynamic> {
  /// Converts this map to a [f.Schema].
  f.Schema toSchema() {
    final jsonSchema = this;
    final type = jsonSchema['type'] as String;
    final description = jsonSchema['description'] as String?;
    _logger.fine('Converting schema to Firebase format: type=$type');
    final nullable = jsonSchema['nullable'] as bool?;
    final enumValues = (jsonSchema['enum'] as List?)?.cast<String>();
    final format = jsonSchema['format'] as String?;
    final items = jsonSchema['items'] != null
        ? Map<String, dynamic>.from(jsonSchema['items'] as Map)
        : null;
    final properties = jsonSchema['properties'] != null
        ? Map<String, dynamic>.from(jsonSchema['properties'] as Map)
        : null;
    final requiredProperties = 
        (jsonSchema['required'] as List?)?.cast<String>();

    switch (type) {
      case 'string':
        if (enumValues != null) {
          return f.Schema.enumString(
            enumValues: enumValues,
            description: description,
            nullable: nullable,
          );
        } else {
          return f.Schema.string(description: description, nullable: nullable);
        }
      case 'number':
        return f.Schema.number(
          description: description,
          nullable: nullable,
          format: format,
        );
      case 'integer':
        return f.Schema.integer(
          description: description,
          nullable: nullable,
          format: format,
        );
      case 'boolean':
        return f.Schema.boolean(description: description, nullable: nullable);
      case 'array':
        if (items != null) {
          final itemsSchema = items.toSchema();
          _logger.fine('Converting array schema with items');
          return f.Schema.array(
            items: itemsSchema,
            description: description,
            nullable: nullable,
          );
        }
        throw ArgumentError('Array schema must have "items" property');
      case 'object':
        if (properties != null) {
          final propertiesSchema = properties.map(
            (key, value) => MapEntry(
              key,
              Map<String, dynamic>.from(value as Map).toSchema(),
            ),
          );
          _logger.fine(
            'Converting object schema with ${properties.length} properties',
          );
          return f.Schema.object(
            properties: propertiesSchema,
            optionalProperties: requiredProperties,
            description: description,
            nullable: nullable,
          );
        }
        throw ArgumentError('Object schema must have "properties" property');
      default:
        throw ArgumentError('Invalid schema type: $type');
    }
  }
}
