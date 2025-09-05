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

  // When linking tool results via previous_response_id, only include results
  // that correspond to the tool calls from the most recent assistant turn that
  // actually issued those calls. This avoids sending mismatched historical
  // tool outputs which would cause API errors.
  final allowedToolCallIds = <String>{};
  if (previousResponseId != null) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.role == ChatMessageRole.model) {
        final callIds = m.parts
            .whereType<ToolPart>()
            .where((p) => p.kind == ToolPartKind.call)
            .map((p) => p.id)
            .where((id) => id.isNotEmpty)
            .toSet();
        if (callIds.isNotEmpty) {
          allowedToolCallIds.addAll(callIds);
          break;
        }
      }
    }
  }
  for (final m in messages) {
    if (m.role == ChatMessageRole.system) continue; // handled as instructions

    // Expand tool results to separate messages when necessary
    final toolResults = m.parts.whereType<ToolPart>().where(
      (p) => p.kind == ToolPartKind.result,
    );

    if (toolResults.isNotEmpty) {
      if (previousResponseId != null && allowedToolCallIds.isNotEmpty) {
        // Split tool results into those that belong to the last assistant tool
        // calls (linkable) and those that don't (fallback to text embedding).
        final linkable = <ToolPart>[];
        final fallback = <ToolPart>[];
        for (final tr in toolResults) {
          if (allowedToolCallIds.contains(tr.id)) {
            linkable.add(tr);
          } else {
            fallback.add(tr);
          }
        }

        if (linkable.isNotEmpty) {
          logger.info(
            'Converting ${linkable.length} tool results to '
            'function_call_output '
            '(linking to previous_response_id) and embedding '
            '${fallback.length} as text',
          );
          for (final tr in linkable) {
            logger.fine(
              'Sending function_call_output: call_id=${tr.id}, name=${tr.name}',
            );
            input.add({
              'type': 'function_call_output',
              'call_id': tr.id,
              'output': _serializeToolResult(tr.result),
            });
          }
        }

        if (fallback.isNotEmpty) {
          final textBlocks = fallback
              .map(
                (tr) =>
                    'Tool result ${tr.name}: '
                    '${_serializeToolResult(tr.result)}',
              )
              .toList();
          input.add({
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': textBlocks.join('\n')},
            ],
          });
        }

        continue;
      } else {
        // previous_response_id not available (e.g., provider switch), or we
        // don't know which tool calls to link: embed as text context.
        final textBlocks = <String>[];
        for (final tr in toolResults) {
          final serialized = _serializeToolResult(tr.result);
          textBlocks.add('Tool result ${tr.name}: $serialized');
        }
        input.add({
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': textBlocks.join('\n')},
          ],
        });
        continue;
      }
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
              // Responses API expects input_image with image_url for inline
              // data. Using data URL ensures broad compatibility across
              // models (avoids unknown 'image' parameter errors).
              final base64Data = base64.encode(bytes);
              content.add({
                'type': 'input_image',
                'image_url': 'data:$mimeType;base64,$base64Data',
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

  // Typed output via native Responses API text.format (response_format moved)
  final rf = _createResponseFormat(outputSchema);
  if (rf != null) {
    request['text'] = {'format': rf};
  }

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
  // Temperature is not supported for some Responses models (e.g., gpt-5),
  // and the API returns 400 when present. Omit it for maximum compatibility.
  final mergedTopP = options?.topP ?? defaultOptions.topP;
  final mergedMaxTokens = options?.maxTokens ?? defaultOptions.maxTokens;
  final mergedStop = options?.stop ?? defaultOptions.stop;
  final mergedSeed = options?.seed ?? defaultOptions.seed;
  final mergedParallelToolCalls =
      options?.parallelToolCalls ?? defaultOptions.parallelToolCalls;
  final mergedUser = options?.user ?? defaultOptions.user;
  final mergedToolChoice = options?.toolChoice ?? defaultOptions.toolChoice;

  // Intentionally not sending temperature in Responses API payload
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
  // For the Responses API, the format object expects the schema fields at the
  // top level under text.format (not nested under json_schema)
  return {
    'type': 'json_schema',
    'name': 'output_schema',
    'description': 'Generated response following the provided schema',
    'schema': _openaiStrictSchemaFrom(
      Map<String, dynamic>.from(outputSchema.schemaMap ?? {}),
    ),
    'strict': true,
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
