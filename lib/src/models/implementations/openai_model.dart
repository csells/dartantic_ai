import 'dart:convert';
import 'dart:typed_data';

import 'package:json_schema/json_schema.dart';
import 'package:openai_dart/openai_dart.dart' as openai;
import 'package:uuid/uuid.dart';

import '../../../dartantic_ai.dart';
import '../../utils.dart';

/// Implementation of [Model] that uses OpenAI's API.
///
/// This model handles interaction with OpenAI models, supporting both
/// standard text responses and structured JSON schema responses.
class OpenAiModel extends Model {
  /// Creates a new [OpenAiModel] with the given parameters.
  ///
  /// The [apiKey] is the API key to use for authentication.
  /// The [modelName] is the name of the OpenAI model to use.
  /// The [embeddingModelName] is the name of the OpenAI embedding model to use.
  /// The [outputSchema] is an optional JSON schema for structured outputs.
  /// The [systemPrompt] is an optional system prompt to use.
  OpenAiModel({
    required String apiKey,
    required this.caps,
    String? modelName,
    String? embeddingModelName,
    Uri? baseUrl,
    JsonSchema? outputSchema,
    String? systemPrompt,
    Iterable<Tool>? tools,
    double? temperature,
  }) : generativeModelName = modelName ?? defaultModelName,
       embeddingModelName = embeddingModelName ?? defaultEmbeddingModelName,
       _tools = tools?.toList(),
       _systemPrompt = systemPrompt,
       _client = openai.OpenAIClient(
         apiKey: apiKey,
         baseUrl: baseUrl?.toString(),
       ),
       _responseFormat =
           outputSchema != null
               ? openai.ResponseFormat.jsonSchema(
                 jsonSchema: _openaiSchemaFrom(outputSchema),
               )
               : null,
       _temperature = temperature;

  /// The default model name to use if none is provided.
  static const defaultModelName = 'gpt-4o';

  /// The default embedding model name to use if none is provided.
  static const defaultEmbeddingModelName = 'text-embedding-3-small';

  final openai.OpenAIClient _client;
  final openai.ResponseFormat? _responseFormat;
  final String? _systemPrompt;
  final List<Tool>? _tools;
  final double? _temperature;
  final Map<String, String> _toolCallIdToName = {};

  @override
  final String generativeModelName;

  @override
  final String embeddingModelName;

  @override
  Stream<AgentResponse> runStream({
    required String prompt,
    required Iterable<Message> messages,
    required Iterable<Part> attachments,
  }) async* {
    var isFirstEverTextResponse = true;
    log.finer(
      '[OpenAiModel] Starting stream with ${messages.length} messages, '
      'prompt length: ${prompt.length}',
    );

    final message = Message.user([TextPart(prompt), ...attachments]);
    final oiaMessages = <openai.ChatCompletionMessage>[
      if (_systemPrompt != null && _systemPrompt.isNotEmpty && messages.isEmpty)
        openai.ChatCompletionMessage.system(content: _systemPrompt),
      ..._openaiMessagesFrom(messages),
      _openaiMessagesFrom([message]).first,
    ];

    final stream = _client.createChatCompletionStream(
      request: openai.CreateChatCompletionRequest(
        model: openai.ChatCompletionModel.modelId(generativeModelName),
        responseFormat: _responseFormat,
        messages: oiaMessages,
        temperature: _temperature,
      ),
    );

    final chunks = <String>[];
    final toolCalls = <openai.ChatCompletionMessageToolCall>[];

    // Accumulate tool call data during streaming
    final toolCallIdByIndex = <int, String?>{};
    final toolCallBuffers = <String, ({String name, StringBuffer args})>{};
    var syntheticIndex = 0;
    var isFirstTextChunk = true;

    await for (final chunk in stream) {
      final choice = chunk.choices.first;
      final delta = choice.delta;

      log.finest(
        '[OpenAiModel] Raw delta: $delta, '
        'finishReason: ${choice.finishReason}',
      );

      // fix for https://github.com/davidmigloz/langchain_dart/issues/726
      if (delta == null) continue;

      // Handle content streaming
      if (delta.content != null && delta.content!.isNotEmpty) {
        var outputText = delta.content!;
        if (isFirstTextChunk) {
          if (!isFirstEverTextResponse) {
            outputText = '\n$outputText';
          }
          isFirstEverTextResponse = false;
          isFirstTextChunk = false;
        }
        chunks.add(delta.content!);
        yield AgentResponse(output: outputText, messages: []);
      }

      // Handle tool calls during streaming
      if (delta.toolCalls != null && delta.toolCalls!.isNotEmpty) {
        final callsDesc = delta.toolCalls!
            .where((tc) => tc.function?.name != null)
            .map(
              (tc) => '${tc.function!.name}(${tc.function?.arguments ?? ''})',
            )
            .join(', ');
        if (callsDesc.isNotEmpty) {
          log.finer('[OpenAiModel] Tool calls received: $callsDesc');
        }

        for (final toolCall in delta.toolCalls!) {
          final index = toolCall.index ?? syntheticIndex++;
          final id = toolCall.id;
          final name = toolCall.function?.name;
          final args = toolCall.function?.arguments;

          // If this chunk starts a new tool call, record its id and name
          if (id != null && name != null) {
            // Generate synthetic ID if empty
            final actualId = id.isEmpty ? const Uuid().v4() : id;
            toolCallIdByIndex[index] = actualId;
            toolCallBuffers.putIfAbsent(
              actualId,
              () => (name: name, args: StringBuffer()),
            );
          }
          // Use the most recent id for this index
          final currentId = toolCallIdByIndex[index];
          if (currentId != null && args != null) {
            toolCallBuffers[currentId]!.args.write(args);
            log.finer(
              '[OpenAiModel] Tool call received: index=$index, '
              'id=$currentId, name=${toolCallBuffers[currentId]!.name}, '
              'args=$args',
            );
          }
        }
      }
    }

    // Convert tool call buffers to tool calls
    if (toolCallBuffers.isNotEmpty) {
      // Remove incomplete tool call buffers (empty or invalid JSON)
      toolCallBuffers.removeWhere((_, v) {
        final argsStr = v.args.toString().trim();
        if (argsStr.isEmpty) return true;
        try {
          jsonDecode(argsStr);
          return false;
        } on Exception catch (_) {
          return true;
        }
      });

      final validToolCalls =
          toolCallBuffers.entries
              .map(
                (entry) => openai.ChatCompletionMessageToolCall(
                  id: entry.key,
                  type: openai.ChatCompletionMessageToolCallType.function,
                  function: openai.ChatCompletionMessageFunctionCall(
                    name: entry.value.name,
                    arguments: entry.value.args.toString(),
                  ),
                ),
              )
              .toList();

      toolCalls.addAll(validToolCalls);
    }

    // Add the first assistant message to the history. It may have text, tool
    // calls, or both.
    final assistantMessageContent = chunks.join();
    if (assistantMessageContent.isNotEmpty || toolCalls.isNotEmpty) {
      oiaMessages.add(
        openai.ChatCompletionMessage.assistant(
          content:
              assistantMessageContent.isNotEmpty
                  ? assistantMessageContent
                  : null,
          toolCalls: toolCalls.isNotEmpty ? toolCalls.toList() : null,
        ),
      );
    }

    // Main loop following the user's algorithm
    var hasProbedCurrentText = false;
    while (true) {
      // If there are tool calls in our queue, execute them.
      if (toolCalls.isNotEmpty) {
        // Reset the probe flag since we have new activity.
        hasProbedCurrentText = false;

        // Add tool calls to persistent mapping for result lookup
        for (final toolCall in toolCalls) {
          _toolCallIdToName[toolCall.id] = toolCall.function.name;
        }

        // Execute all tool calls and add their results to the history
        for (final toolCall in toolCalls) {
          log.fine(
            '[OpenAiModel] Calling tool: '
            'name=${toolCall.function.name}, args=${toolCall.function.arguments}',
          );
          try {
            final args =
                jsonDecode(toolCall.function.arguments) as Map<String, dynamic>;
            final result = await _callTool(toolCall.function.name, args);
            oiaMessages.add(
              openai.ChatCompletionMessage.tool(
                toolCallId: toolCall.id,
                content: jsonEncode(result),
              ),
            );
          } on Exception catch (ex) {
            log.severe('[OpenAiModel] Error calling tool: $ex');
            oiaMessages.add(
              openai.ChatCompletionMessage.tool(
                toolCallId: toolCall.id,
                content: jsonEncode({'error': ex.toString()}),
              ),
            );
          }
        }

        // Clear the executed tool calls
        toolCalls.clear();

        // Call the model with the tool results
        log.fine('[OpenAiModel] Sending tool responses back to model');
        final stream = _client.createChatCompletionStream(
          request: openai.CreateChatCompletionRequest(
            model: openai.ChatCompletionModel.modelId(generativeModelName),
            responseFormat: _responseFormat,
            messages: oiaMessages,
            temperature: _temperature,
          ),
        );

        final chunks = <String>[];
        final toolCallBuffers = <String, ({String name, StringBuffer args})>{};
        var syntheticIndex = 0;
        final toolCallIdByIndex = <int, String?>{};
        var isFirstTextChunk = true;

        await for (final chunk in stream) {
          final choice = chunk.choices.first;
          final delta = choice.delta;
          if (delta == null) continue;

          // Stream text as it arrives
          if (delta.content != null && delta.content!.isNotEmpty) {
            var outputText = delta.content!;
            if (isFirstTextChunk) {
              if (!isFirstEverTextResponse) {
                outputText = '\n$outputText';
              }
              isFirstEverTextResponse = false;
              isFirstTextChunk = false;
            }
            chunks.add(delta.content!);
            yield AgentResponse(output: outputText, messages: const []);
          }

          // Buffer tool calls
          if (delta.toolCalls != null && delta.toolCalls!.isNotEmpty) {
            for (final toolCall in delta.toolCalls!) {
              final index = toolCall.index ?? syntheticIndex++;
              final id = toolCall.id;
              final name = toolCall.function?.name;
              final args = toolCall.function?.arguments;

              if (id != null && name != null) {
                final actualId = id.isEmpty ? const Uuid().v4() : id;
                toolCallIdByIndex[index] = actualId;
                toolCallBuffers.putIfAbsent(
                  actualId,
                  () => (name: name, args: StringBuffer()),
                );
              }
              final currentId = toolCallIdByIndex[index];
              if (currentId != null && args != null) {
                toolCallBuffers[currentId]!.args.write(args);
              }
            }
          }
        }

        // Process the streamed response
        final newToolCalls = <openai.ChatCompletionMessageToolCall>[];
        if (toolCallBuffers.isNotEmpty) {
          toolCallBuffers.removeWhere((_, v) {
            final argsStr = v.args.toString().trim();
            if (argsStr.isEmpty) return true;
            try {
              jsonDecode(argsStr);
              return false;
            } on Exception catch (_) {
              return true;
            }
          });
          newToolCalls.addAll(
            toolCallBuffers.entries.map(
              (entry) => openai.ChatCompletionMessageToolCall(
                id: entry.key,
                type: openai.ChatCompletionMessageToolCallType.function,
                function: openai.ChatCompletionMessageFunctionCall(
                  name: entry.value.name,
                  arguments: entry.value.args.toString(),
                ),
              ),
            ),
          );
        }

        // Add the completed assistant message to history
        final newContent = chunks.join();
        if (newContent.isNotEmpty || newToolCalls.isNotEmpty) {
          final sanitizedMessage =
              (newToolCalls.isEmpty)
                  ? openai.ChatCompletionMessage.assistant(
                    content: newContent,
                    toolCalls: null,
                  )
                  : openai.ChatCompletionMessage.assistant(
                    content: newContent.isNotEmpty ? newContent : null,
                    toolCalls: newToolCalls,
                  );
          oiaMessages.add(sanitizedMessage);
        }

        // If the response has new tool calls, add them to the queue and loop.
        if (newToolCalls.isNotEmpty) {
          toolCalls.addAll(newToolCalls);
          continue;
        }
      }

      // If there are no tool calls, check if we should probe.
      final lastMessage = oiaMessages.lastOrNull;
      if (!hasProbedCurrentText &&
          lastMessage is openai.ChatCompletionAssistantMessage &&
          (lastMessage.content?.isNotEmpty ?? false)) {
        // Set flag to true so we don't probe this same text again.
        hasProbedCurrentText = true;

        log.fine(
          '[OpenAiModel] Probing for more tool calls after text response',
        );
        try {
          final stream = _client.createChatCompletionStream(
            request: openai.CreateChatCompletionRequest(
              model: openai.ChatCompletionModel.modelId(generativeModelName),
              responseFormat: _responseFormat,
              messages: [
                ...oiaMessages,
                const openai.ChatCompletionMessage.user(
                  content: openai.ChatCompletionUserMessageContent.string(''),
                ),
              ],
              tools:
                  _tools
                      ?.map(
                        (tool) => openai.ChatCompletionTool(
                          type: openai.ChatCompletionToolType.function,
                          function: openai.FunctionObject(
                            name: tool.name,
                            description: tool.description,
                            parameters: tool.inputSchema?.toMap(),
                          ),
                        ),
                      )
                      .toList(),
              temperature: _temperature,
            ),
          );

          final chunks = <String>[];
          final toolCallBuffers =
              <String, ({String name, StringBuffer args})>{};
          var syntheticIndex = 0;
          final toolCallIdByIndex = <int, String?>{};
          var isFirstTextChunk = true;

          await for (final chunk in stream) {
            final choice = chunk.choices.first;
            final delta = choice.delta;
            if (delta == null) continue;

            // Stream text as it arrives
            if (delta.content != null && delta.content!.isNotEmpty) {
              var outputText = delta.content!;
              if (isFirstTextChunk) {
                if (!isFirstEverTextResponse) {
                  outputText = '\n$outputText';
                }
                isFirstEverTextResponse = false;
                isFirstTextChunk = false;
              }
              chunks.add(delta.content!);
              yield AgentResponse(output: outputText, messages: const []);
            }

            // Buffer tool calls
            if (delta.toolCalls != null && delta.toolCalls!.isNotEmpty) {
              for (final toolCall in delta.toolCalls!) {
                final index = toolCall.index ?? syntheticIndex++;
                final id = toolCall.id;
                final name = toolCall.function?.name;
                final args = toolCall.function?.arguments;

                if (id != null && name != null) {
                  final actualId = id.isEmpty ? const Uuid().v4() : id;
                  toolCallIdByIndex[index] = actualId;
                  toolCallBuffers.putIfAbsent(
                    actualId,
                    () => (name: name, args: StringBuffer()),
                  );
                }
                final currentId = toolCallIdByIndex[index];
                if (currentId != null && args != null) {
                  toolCallBuffers[currentId]!.args.write(args);
                }
              }
            }
          }

          // Process the streamed response
          final newToolCalls = <openai.ChatCompletionMessageToolCall>[];
          if (toolCallBuffers.isNotEmpty) {
            toolCallBuffers.removeWhere((_, v) {
              final argsStr = v.args.toString().trim();
              if (argsStr.isEmpty) return true;
              try {
                jsonDecode(argsStr);
                return false;
              } on Exception catch (_) {
                return true;
              }
            });
            newToolCalls.addAll(
              toolCallBuffers.entries.map(
                (entry) => openai.ChatCompletionMessageToolCall(
                  id: entry.key,
                  type: openai.ChatCompletionMessageToolCallType.function,
                  function: openai.ChatCompletionMessageFunctionCall(
                    name: entry.value.name,
                    arguments: entry.value.args.toString(),
                  ),
                ),
              ),
            );
          }

          // Add the completed assistant message to history
          final newContent = chunks.join();
          if (newContent.isNotEmpty || newToolCalls.isNotEmpty) {
            final sanitizedMessage =
                (newToolCalls.isEmpty)
                    ? openai.ChatCompletionMessage.assistant(
                      content: newContent,
                      toolCalls: null,
                    )
                    : openai.ChatCompletionMessage.assistant(
                      content: newContent.isNotEmpty ? newContent : null,
                      toolCalls: newToolCalls,
                    );
            oiaMessages.add(sanitizedMessage);
          }

          // If the probe found new tools, add them to the queue and loop.
          if (newToolCalls.isNotEmpty) {
            toolCalls.addAll(newToolCalls);
            continue;
          }
        } on Exception catch (e) {
          log.warning('[OpenAiModel] Probe failed: $e');
        }

        // If we get here, the probe failed or found no more tools.
        // The last message is the final one, so we can exit.
        break;
      }

      // If we've reached here, there are no more tools and probing is done.
      break;
    }

    // Yield the final response with the complete message history.
    yield AgentResponse(output: '', messages: _messagesFrom(oiaMessages));
  }

  @override
  Future<Float64List> createEmbedding(
    String text, {
    EmbeddingType type = EmbeddingType.document,
  }) async {
    if (!caps.contains(ProviderCaps.embeddings)) {
      throw Exception('Embeddings are not supported by this provider.');
    }

    final request = openai.CreateEmbeddingRequest(
      model: openai.EmbeddingModel.modelId(embeddingModelName),
      input: openai.EmbeddingInput.string(text),
    );

    final response = await _client.createEmbedding(request: request);
    final embeddingVector = response.data.first.embedding;

    if (embeddingVector is openai.EmbeddingVectorListDouble) {
      return Float64List.fromList(embeddingVector.value);
    } else if (embeddingVector is openai.EmbeddingVectorString) {
      // Decode base64 encoded embedding to float values
      final base64String = embeddingVector.value;
      final bytes = base64Decode(base64String);
      return Float64List.view(bytes.buffer);
    } else {
      throw UnsupportedError(
        'Unknown embedding vector type: ${embeddingVector.runtimeType}',
      );
    }
  }

  Future<Map<String, dynamic>?> _callTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    Map<String, dynamic>? result;
    try {
      // if the tool isn't found, return an error
      final tool = _tools?.where((t) => t.name == name).singleOrNull;
      result =
          tool == null
              ? {'error': 'Tool $name not found'}
              : await tool.onCall.call(args);
    } on Exception catch (ex) {
      // if the tool call throws an error, return the exception message
      result = {'error': ex.toString()};
    }

    log.fine('Tool: $name($args)= $result');
    return result;
  }

  static openai.JsonSchemaObject _openaiSchemaFrom(
    JsonSchema rawJsonSchema, {
    String name = 'response',
    bool strict = true,
  }) {
    // Ensure additionalProperties: false is set at every object level
    final jsonSchema = rawJsonSchema.toMap();
    final schema = _ensureAdditionalPropertiesFalse(jsonSchema);

    return openai.JsonSchemaObject(
      name: name,
      description: schema['description'] as String?,
      schema: schema,
      strict: strict,
    );
  }

  static Map<String, Object> _ensureAdditionalPropertiesFalse(
    Map<String, dynamic> schema,
  ) {
    final result = Map<String, Object>.from(schema);

    // Skip adding additionalProperties if $ref is present
    if (!result.containsKey(r'$ref')) {
      // Set additionalProperties: false for this object
      result['additionalProperties'] = false;
    }

    // Remove format field if it exists
    result.remove('format');

    // Handle properties of objects
    if (result['properties'] is Map) {
      final properties = Map<String, Object>.from(result['properties']! as Map);
      for (final entry in properties.entries) {
        if (entry.value is Map) {
          properties[entry.key] = _ensureAdditionalPropertiesFalse(
            entry.value as Map<String, dynamic>,
          );
        }
      }
      result['properties'] = properties;
    }

    // Handle items of arrays
    if (result['items'] is Map) {
      result['items'] = _ensureAdditionalPropertiesFalse(
        result['items']! as Map<String, dynamic>,
      );
    }

    // Handle definitions
    if (result[r'$defs'] is Map) {
      final definitions = Map<String, Object>.from(result[r'$defs']! as Map);
      for (final entry in definitions.entries) {
        if (entry.value is Map) {
          definitions[entry.key] = _ensureAdditionalPropertiesFalse(
            entry.value as Map<String, dynamic>,
          );
        }
      }
      result[r'$defs'] = definitions;
    }

    return result;
  }

  static Iterable<openai.ChatCompletionMessage> _openaiMessagesFrom(
    Iterable<Message> messages,
  ) {
    final result = <openai.ChatCompletionMessage>[];
    for (final message in messages) {
      // Gather tool calls and tool results
      final toolCalls = <openai.ChatCompletionMessageToolCall>[];
      ToolPart? toolResult;
      final textParts = <String>[];
      for (final part in message.parts) {
        if (part is TextPart) {
          textParts.add(part.text);
        } else if (part is LinkPart) {
          textParts.add('[media: ${part.mimeType}] ${part.url}');
        } else if (part is DataPart) {
          final base64 = base64Encode(part.bytes);
          final mimeType = part.mimeType;
          textParts.add('[media: $mimeType] data:$mimeType;base64,$base64');
        } else if (part is ToolPart) {
          switch (part.kind) {
            case ToolPartKind.call:
              toolCalls.add(
                openai.ChatCompletionMessageToolCall(
                  id: part.id,
                  type: openai.ChatCompletionMessageToolCallType.function,
                  function: openai.ChatCompletionMessageFunctionCall(
                    name: part.name,
                    arguments: jsonEncode(part.arguments),
                  ),
                ),
              );
            case ToolPartKind.result:
              toolResult = part;
          }
        }
      }

      final contentString = textParts.join(' ');

      if (toolResult != null) {
        // Tool result: emit a tool role message
        result.add(
          openai.ChatCompletionMessage.tool(
            toolCallId: toolResult.id,
            content: jsonEncode(toolResult.result),
          ),
        );
      } else if (toolCalls.isNotEmpty) {
        // Tool call: emit an assistant message with toolCalls
        result.add(
          openai.ChatCompletionMessage.assistant(
            content: contentString.isNotEmpty ? contentString : null,
            toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
          ),
        );
      } else {
        // Regular message
        switch (message.role) {
          case MessageRole.system:
            result.add(
              openai.ChatCompletionMessage.system(content: contentString),
            );
          case MessageRole.user:
            result.add(
              openai.ChatCompletionMessage.user(
                content: openai.ChatCompletionUserMessageContent.string(
                  contentString,
                ),
              ),
            );
          case MessageRole.model:
            result.add(
              openai.ChatCompletionMessage.assistant(
                content: contentString,
                toolCalls: null,
              ),
            );
        }
      }
    }

    return result;
  }

  Iterable<Message> _messagesFrom(
    Iterable<openai.ChatCompletionMessage> openMessages,
  ) {
    // Second pass: convert messages
    final result = <Message>[];
    for (final message in openMessages) {
      final parts = <Part>[];
      if (message.role == openai.ChatCompletionMessageRole.tool) {
        // Tool result: parse content as JSON and create ToolPart(kind: result)
        final content = message.content;
        if (content is String && content.isNotEmpty) {
          try {
            final resultJson = jsonDecode(content);
            final toolCallId =
                message is openai.ChatCompletionToolMessage
                    ? message.toolCallId
                    : '';
            final toolName = _toolCallIdToName[toolCallId];
            if (toolName == null || toolName.isEmpty) {
              throw StateError(
                'Tool call ID "$toolCallId" not found in mapping. '
                'Available IDs: ${_toolCallIdToName.keys.toList()}. '
                'This indicates a problem with tool call ID tracking.',
              );
            }
            parts.add(
              ToolPart(
                kind: ToolPartKind.result,
                id: toolCallId,
                name: toolName,
                result:
                    resultJson is Map<String, dynamic>
                        ? resultJson
                        : <String, dynamic>{},
              ),
            );
          } on Exception catch (_) {
            parts.add(TextPart(content));
          }
        }
      } else {
        // Handle content first
        if (message.content is String) {
          parts.add(TextPart(message.content! as String));
        } else if (message.content is List) {
          for (final c in message.content! as List) {
            if (c is String) {
              parts.add(TextPart(c));
            }
          }
        } else if (message.content is openai.ChatCompletionUserMessageContent) {
          final userContent =
              message.content! as openai.ChatCompletionUserMessageContent;
          parts.add(TextPart(userContent.value as String));
        }

        // Handle tool calls for assistant messages
        if (message.role == openai.ChatCompletionMessageRole.assistant &&
            message is openai.ChatCompletionAssistantMessage) {
          final assistantMsg = message;
          final toolCalls = assistantMsg.toolCalls;
          if (toolCalls != null) {
            for (final call in toolCalls) {
              // Generate synthetic ID if empty (some providers like Gemini
              // may not provide them)
              final toolCallId = call.id.isEmpty ? const Uuid().v4() : call.id;
              parts.add(
                ToolPart(
                  kind: ToolPartKind.call,
                  id: toolCallId,
                  name: call.function.name,
                  arguments: () {
                    try {
                      final decoded = jsonDecode(call.function.arguments);
                      return decoded is Map<String, dynamic>
                          ? decoded
                          : <String, dynamic>{};
                    } on Exception catch (_) {
                      return <String, dynamic>{};
                    }
                  }(),
                ),
              );
            }
          }
        }
      }

      // Assert no empty parts
      assert(
        parts.isNotEmpty || message.content == null,
        'Message should never have empty parts: ${message.role}',
      );

      // only add message if it has parts
      if (parts.isNotEmpty) {
        result.add(Message(role: message.role.messageRole, parts: parts));
      }
    }

    assert(
      result.length == openMessages.length,
      r'Output message list length (${result.length}) does not match input '
      'message list length (${openMessages.length})',
    );

    return result;
  }

  /// The capabilities of the model.
  @override
  final Set<ProviderCaps> caps;
}

extension on openai.ChatCompletionMessageRole {
  MessageRole get messageRole => switch (this) {
    openai.ChatCompletionMessageRole.system => MessageRole.system,
    openai.ChatCompletionMessageRole.user => MessageRole.user,
    openai.ChatCompletionMessageRole.assistant => MessageRole.model,
    openai.ChatCompletionMessageRole.tool => MessageRole.model,
    _ => MessageRole.model,
  };
}
