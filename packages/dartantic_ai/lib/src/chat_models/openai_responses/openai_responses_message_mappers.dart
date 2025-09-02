import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';

import '../../agent/tool_constants.dart';
import 'openai_responses_chat_options.dart';

/// Builds a request payload for the OpenAI Responses API from unified messages.
Map<String, dynamic> buildResponsesRequest(
  List<ChatMessage> messages, {
  required String modelName,
  required OpenAIResponsesChatOptions defaultOptions,
  List<Tool>? tools,
  double? temperature,
  OpenAIResponsesChatOptions? options,
  JsonSchema? outputSchema,
}) {
  final request = <String, dynamic>{'model': modelName};

  // Collect system instructions (concatenate all system texts)
  final systemTexts = <String>[];
  for (final m in messages) {
    if (m.role == ChatMessageRole.system) {
      final text = m.parts.whereType<TextPart>().map((p) => p.text).join();
      if (text.isNotEmpty) systemTexts.add(text);
    }
  }
  if (systemTexts.isNotEmpty) {
    request['instructions'] = systemTexts.join('\n\n');
  }

  // Convert messages to Responses `input` array
  final input = <Map<String, dynamic>>[];
  for (final m in messages) {
    if (m.role == ChatMessageRole.system) continue; // handled as instructions

    // Expand tool results to separate messages when necessary
    final toolResults = m.parts.whereType<ToolPart>().where(
      (p) => p.kind == ToolPartKind.result,
    );

    if (toolResults.isNotEmpty) {
      for (final tr in toolResults) {
        input.add({
          'role': 'tool',
          'id': tr.id,
          'name': tr.name,
          // Many variants accept either content or a structured tool_result.
          // We use a plain text payload for broad compatibility; providers
          // parse this as the tool's output content.
          'content': [
            {'type': 'output_text', 'text': _serializeToolResult(tr.result)},
          ],
        });
      }
      // Skip adding the original message parts (tool results handled above)
      continue;
    }

    final role = switch (m.role) {
      ChatMessageRole.user => 'user',
      ChatMessageRole.model => 'assistant',
      ChatMessageRole.system => 'system', // excluded earlier, but safe default
    };

    final content = <Map<String, dynamic>>[];
    for (final part in m.parts) {
      switch (part) {
        case TextPart(:final text):
          if (text.isNotEmpty) {
            content.add({
              'type': role == 'assistant' ? 'output_text' : 'input_text',
              'text': text,
            });
          }
        case DataPart(:final bytes, :final mimeType):
          if (mimeType.startsWith('image/')) {
            if (role == 'user') {
              content.add({
                'type': 'input_image',
                'image': {'data': base64.encode(bytes), 'mime_type': mimeType},
              });
            }
          } else {
            // Non-image binary: embed as text hint with data URL (user only)
            if (role == 'user') {
              content.add({
                'type': 'input_text',
                'text':
                    '[media: $mimeType] '
                    'data:$mimeType;base64,${base64.encode(bytes)}',
              });
            }
          }
        case LinkPart(:final url):
          if (role == 'user') {
            content.add({'type': 'input_image', 'image_url': url.toString()});
          }
        case ToolPart():
          // Tool calls are never part of user/assistant input
          // They are handled via streaming responses from the model.
          break;
      }
    }

    input.add({
      'role': role,
      'content': content.isEmpty
          ? [
              {
                'type': role == 'assistant' ? 'output_text' : 'input_text',
                'text': '',
              },
            ]
          : content,
    });
  }

  if (input.isNotEmpty) request['input'] = input;

  // Tools mapping (filter out return_result - native typed output supported)
  final toolDefs = tools
      ?.where((t) => t.name != kReturnResultToolName)
      .map(
        (tool) => {
          'type': 'function',
          'function': {
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.inputSchema.schemaMap,
          },
        },
      )
      .toList();
  if (toolDefs != null && toolDefs.isNotEmpty) request['tools'] = toolDefs;

  // Typed output via native response_format
  final rf = _createResponseFormat(outputSchema);
  if (rf != null) request['response_format'] = rf;

  // Reasoning configuration (effort + summary)
  final effort = options?.reasoningEffort ?? defaultOptions.reasoningEffort;
  final summary = options?.reasoningSummary ?? defaultOptions.reasoningSummary;
  if (effort != null || summary != null) {
    final reasoning = <String, dynamic>{};
    if (effort != null) {
      reasoning['effort'] = switch (effort) {
        OpenAIReasoningEffort.low => 'low',
        OpenAIReasoningEffort.medium => 'medium',
        OpenAIReasoningEffort.high => 'high',
      };
    }
    if (summary != null) {
      reasoning['summary'] = switch (summary) {
        OpenAIReasoningSummary.brief => 'brief',
        OpenAIReasoningSummary.detailed => 'detailed',
      };
    }
    request['reasoning'] = reasoning;
  }

  // Options merging (favor explicit args, then options, then defaults)
  final mergedTemperature =
      temperature ?? options?.temperature ?? defaultOptions.temperature;
  final mergedTopP = options?.topP ?? defaultOptions.topP;
  final mergedMaxTokens = options?.maxTokens ?? defaultOptions.maxTokens;
  final mergedStop = options?.stop ?? defaultOptions.stop;
  final mergedSeed = options?.seed ?? defaultOptions.seed;
  final mergedParallelToolCalls =
      options?.parallelToolCalls ?? defaultOptions.parallelToolCalls;
  final mergedUser = options?.user ?? defaultOptions.user;
  final mergedToolChoice = options?.toolChoice ?? defaultOptions.toolChoice;

  if (mergedTemperature != null) request['temperature'] = mergedTemperature;
  if (mergedTopP != null) request['top_p'] = mergedTopP;
  if (mergedMaxTokens != null) {
    // Include both fields for compatibility
    request['max_output_tokens'] = mergedMaxTokens;
    request['max_tokens'] = mergedMaxTokens;
  }
  if (mergedStop != null && mergedStop.isNotEmpty) request['stop'] = mergedStop;
  if (mergedSeed != null) request['seed'] = mergedSeed;
  if (mergedParallelToolCalls != null) {
    request['parallel_tool_calls'] = mergedParallelToolCalls;
  }
  if (mergedUser != null) request['user'] = mergedUser;
  if (mergedToolChoice != null) request['tool_choice'] = mergedToolChoice;

  // Request streaming mode
  request['stream'] = true;

  return request;
}

/// Convert a tool result into the string payload used by Responses input.
String _serializeToolResult(Object? result) {
  // Tool results may already be strings or structured JSON; stringify uniformly
  if (result == null) return '';
  if (result is String) return result;
  return json.encode(result);
}

/// Creates a native response_format from a JsonSchema, if provided.
Map<String, dynamic>? _createResponseFormat(JsonSchema? outputSchema) {
  if (outputSchema == null) return null;
  return {
    'type': 'json_schema',
    'json_schema': {
      'name': 'output_schema',
      'description': 'Generated response following the provided schema',
      'schema': _openaiStrictSchemaFrom(
        Map<String, dynamic>.from(outputSchema.schemaMap ?? {}),
      ),
      'strict': true,
    },
  };
}

/// Converts JsonSchema to the OpenAI strict schema format expected by
/// Responses.
Map<String, dynamic> _openaiStrictSchemaFrom(Map<String, dynamic> schema) {
  final result = Map<String, dynamic>.from(schema);

  // Normalize nullable union types to non-null where possible
  if (result['type'] is List) {
    final types = (result['type'] as List).where((t) => t != 'null').toList();
    if (types.length == 1) result['type'] = types.first;
  }

  // Remove unsupported format fields
  result.remove('format');

  if (result['type'] == 'object') {
    result['additionalProperties'] = false;
    final props = result['properties'] as Map<String, dynamic>?;
    if (props != null) {
      final processed = <String, dynamic>{};
      for (final entry in props.entries) {
        processed[entry.key] = _openaiStrictSchemaFrom(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
      result['properties'] = processed;
      result['required'] = props.keys.toList();
    } else {
      result['properties'] = <String, dynamic>{};
      result['required'] = <String>[];
    }
  }

  if (result['type'] == 'array') {
    final items = result['items'] as Map<String, dynamic>?;
    if (items != null) {
      result['items'] = _openaiStrictSchemaFrom(
        Map<String, dynamic>.from(items),
      );
    }
  }

  // Process definitions if present
  final defs = result['definitions'] as Map<String, dynamic>?;
  if (defs != null) {
    final processed = <String, dynamic>{};
    for (final entry in defs.entries) {
      processed[entry.key] = _openaiStrictSchemaFrom(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
    result['definitions'] = processed;
  }

  return result;
}
