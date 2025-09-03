import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

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
  String? previousResponseId,
}) {
  // Local logger for request mapping
  final logger = Logger('dartantic.chat.models.openai_responses.mapper');
  final request = <String, dynamic>{'model': modelName};

  // Add previous response ID for tool result linking
  if (previousResponseId != null) {
    request['previous_response_id'] = previousResponseId;
  }

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
      // Convert tool results to function_call_output format for Responses API
      logger.info(
        'Converting ${toolResults.length} tool results to function_call_output',
      );
      for (final tr in toolResults) {
        logger.fine(
          'Sending function_call_output: call_id=${tr.id}, name=${tr.name}',
        );
        input.add({
          'type': 'function_call_output',
          'call_id': tr.id,
          'output': _serializeToolResult(tr.result),
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
  final toolDefs = tools?.where((t) => t.name != kReturnResultToolName).map((
    tool,
  ) {
    final originalSchema = tool.inputSchema.schemaMap ?? {};
    return {
      'type': 'function',
      'name': tool.name,
      'description': tool.description,
      'parameters': originalSchema,
    };
  }).toList();
  if (toolDefs != null && toolDefs.isNotEmpty) request['tools'] = toolDefs;

  // Typed output via native response_format
  final rf = _createResponseFormat(outputSchema);
  if (rf != null) request['response_format'] = rf;

  // Reasoning configuration (effort + summary)
  final effort = options?.reasoningEffort ?? defaultOptions.reasoningEffort;
  // Default summary to 'none' when not specified at all (no summary field)
  final selectedSummary =
      options?.reasoningSummary ??
      defaultOptions.reasoningSummary ??
      OpenAIReasoningSummary.none;

  final reasoning = <String, dynamic>{};
  if (effort != null) {
    reasoning['effort'] = switch (effort) {
      OpenAIReasoningEffort.low => 'low',
      OpenAIReasoningEffort.medium => 'medium',
      OpenAIReasoningEffort.high => 'high',
    };
  }
  // Only include 'summary' if not explicitly NONE
  if (selectedSummary != OpenAIReasoningSummary.none) {
    reasoning['summary'] = switch (selectedSummary) {
      OpenAIReasoningSummary.detailed => 'detailed',
      OpenAIReasoningSummary.concise => 'concise',
      OpenAIReasoningSummary.auto => 'auto',
      OpenAIReasoningSummary.none => 'auto', // unreachable due to guard
    };
  }
  if (reasoning.isNotEmpty) {
    request['reasoning'] = reasoning;
  }

  // Debug: log reasoning block and model selection for verification (FINE)
  final r = request['reasoning'];
  final results = messages.any(
    (m) => m.parts.any((p) => p is ToolPart && p.kind == ToolPartKind.result),
  );
  logger.info(
    'Responses request has tool results: $results, '
    'previous_response_id: $previousResponseId',
  );
  logger.fine(
    'Responses request: '
    'model=$modelName, reasoning=${r == null ? 'null' : json.encode(r)}',
  );

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

/// Serializes a tool result to string format for function_call_output
String _serializeToolResult(dynamic result) {
  if (result == null) return '';
  if (result is String) return result;
  if (result is Map || result is List) return json.encode(result);
  return result.toString();
}
