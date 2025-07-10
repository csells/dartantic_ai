import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;

import '../../../dartantic_ai.dart';
import '../../utils.dart';

/// Implementation of [Model] that uses Anthropic's Claude API.
///
/// This model handles interaction with Anthropic's Claude models, supporting
/// text responses, tool calling, and multimedia input. Unlike OpenAI and
/// Gemini, Anthropic does not support native structured JSON schema output.
class AnthropicModel extends Model {
  /// Creates a new [AnthropicModel] with the given parameters.
  AnthropicModel({
    required this.apiKey,
    required this.caps,
    String? modelName,
    String? systemPrompt,
    Iterable<Tool>? tools,
    this.baseUrl = 'https://api.anthropic.com/v1',
    this.headers = const {},
    this.temperature,
    this.maxTokens = 64000,
    this.timeout = const Duration(minutes: 10),
  }) : generativeModelName = modelName ?? 'claude-sonnet-4-20250514',
       _systemPrompt = systemPrompt,
       _tools = tools?.toList(),
       _client = anthropic.AnthropicClient(
         apiKey: apiKey,
         baseUrl: baseUrl,
         headers: headers,
       );

  /// The API key to use for authentication.
  final String apiKey;

  /// The base URL for the API.
  final String baseUrl;

  /// Additional headers to include in requests.
  final Map<String, String> headers;

  /// The temperature to use for generation.
  final double? temperature;

  /// The maximum number of tokens to generate.
  final int maxTokens;

  /// The timeout for requests.
  final Duration timeout;

  /// The system prompt to use.
  final String? _systemPrompt;

  /// The tools to use.
  final List<Tool>? _tools;

  /// The Anthropic client.
  final anthropic.AnthropicClient _client;

  @override
  String get embeddingModelName =>
      throw UnsupportedError('Anthropic does not provide embeddings API');

  @override
  final String generativeModelName;

  @override
  final Set<ProviderCaps> caps;

  @override
  Stream<AgentResponse> runStream({
    required String prompt,
    required Iterable<Message> messages,
    required Iterable<Part> attachments,
  }) async* {
    log.info(
      '[AnthropicModel] Starting stream with ${messages.length} messages',
    );

    try {
      // Convert messages to Anthropic format
      final anthropicMessages = _convertMessages(messages);

      // Add the current user message
      final userParts = [TextPart(prompt), ...attachments];
      anthropicMessages.add(
        anthropic.Message(
          role: anthropic.MessageRole.user,
          content: anthropic.MessageContent.blocks(
            userParts.map(_convertPart).toList(),
          ),
        ),
      );

      // Build the request
      final request = anthropic.CreateMessageRequest(
        model: anthropic.Model.modelId(generativeModelName),
        maxTokens: maxTokens,
        temperature: temperature,
        messages: anthropicMessages,
        system:
            _systemPrompt != null && _systemPrompt.isNotEmpty
                ? anthropic.CreateMessageRequestSystem.text(_systemPrompt)
                : null,
        tools: _tools != null ? _convertTools(_tools) : null,
      );

      yield* _processStream(request, messages, prompt, attachments);
    } catch (e) {
      log.severe('[AnthropicModel] Error generating response stream: $e');
      throw Exception('Failed to generate response stream: $e');
    }
  }

  /// Processes the main streaming logic with tool calling support.
  Stream<AgentResponse> _processStream(
    anthropic.CreateMessageRequest request,
    Iterable<Message> originalMessages,
    String prompt,
    Iterable<Part> attachments,
  ) async* {
    var currentMessages = request.messages;
    final responseBuffer = StringBuffer();

    while (true) {
      final stream = _client.createMessageStream(
        request: request.copyWith(messages: currentMessages),
      );

      // State for current streaming cycle
      final textBuffer = StringBuffer();
      String? currentToolId;
      String? currentToolName;
      final toolInputBuffer = StringBuffer();
      final toolUseBlocks = <Map<String, dynamic>>[];

      await for (final event in stream) {
        switch (event) {
          case anthropic.ContentBlockStartEvent():
            switch (event.contentBlock) {
              case anthropic.TextBlock():
                log.fine('[AnthropicModel] Text block started');
              case anthropic.ToolUseBlock():
                final toolUseBlock =
                    event.contentBlock as anthropic.ToolUseBlock;
                currentToolId = toolUseBlock.id;
                currentToolName = toolUseBlock.name;
                log.fine('[AnthropicModel] Tool use started: $currentToolName');
              case anthropic.ImageBlock():
                log.fine('[AnthropicModel] Image block started');
              case anthropic.ToolResultBlock():
                log.fine('[AnthropicModel] Tool result block started');
            }

          case anthropic.ContentBlockDeltaEvent():
            switch (event.delta) {
              case anthropic.TextBlockDelta():
                final text = event.delta.text;
                textBuffer.write(text);
                yield AgentResponse(output: text, messages: []);
                log.finest('[AnthropicModel] Text delta: $text');

              case anthropic.InputJsonBlockDelta():
                toolInputBuffer.write(event.delta.inputJson);
                log.finest(
                  '[AnthropicModel] Tool input delta: ${event.delta.inputJson}',
                );
            }

          case anthropic.ContentBlockStopEvent():
            log.fine('[AnthropicModel] Content block completed');

            // If we finished a tool use block, save its info
            if (currentToolId != null && currentToolName != null) {
              try {
                final toolInput =
                    toolInputBuffer.isNotEmpty
                        ? jsonDecode(toolInputBuffer.toString())
                            as Map<String, dynamic>
                        : <String, dynamic>{};

                toolUseBlocks.add({
                  'id': currentToolId,
                  'name': currentToolName,
                  'input': toolInput,
                });

                log.fine(
                  '[AnthropicModel] Completed tool use: $currentToolName',
                );
              } on Exception catch (e) {
                log.warning('[AnthropicModel] Failed to parse tool input: $e');
              }

              // Reset tool state
              currentToolId = null;
              currentToolName = null;
              toolInputBuffer.clear();
            }

          case anthropic.MessageStartEvent():
            log.fine('[AnthropicModel] Message started');

          case anthropic.MessageStopEvent():
            log.fine('[AnthropicModel] Message completed');

          case anthropic.MessageDeltaEvent():
            log.fine('[AnthropicModel] Message delta');

          case anthropic.PingEvent():
            log.finest('[AnthropicModel] Ping received');

          case anthropic.ErrorEvent():
            log.severe('[AnthropicModel] Stream error: ${event.error.message}');
            throw Exception('Stream error: ${event.error.message}');
        }
      }

      // Add current response text to final buffer
      final responseText = textBuffer.toString();
      if (responseText.isNotEmpty) {
        responseBuffer.write(responseText);
      }

      // Add assistant response to message history
      final assistantBlocks = <anthropic.Block>[];

      if (responseText.isNotEmpty) {
        assistantBlocks.add(anthropic.Block.text(text: responseText));
      }

      // Add tool use blocks
      assistantBlocks.addAll(
        toolUseBlocks.map(
          (toolUse) => anthropic.Block.toolUse(
            id: toolUse['id'] as String,
            name: toolUse['name'] as String,
            input: toolUse['input'] as Map<String, dynamic>,
          ),
        ),
      );

      if (assistantBlocks.isNotEmpty) {
        currentMessages = [
          ...currentMessages,
          anthropic.Message(
            role: anthropic.MessageRole.assistant,
            content: anthropic.MessageContent.blocks(assistantBlocks),
          ),
        ];
      }

      // If no tool calls, we're done
      if (toolUseBlocks.isEmpty) {
        break;
      }

      // Execute tool calls and add results
      log.fine('[AnthropicModel] Executing ${toolUseBlocks.length} tool calls');
      final toolResults = <anthropic.Block>[];

      for (final toolUse in toolUseBlocks) {
        try {
          final toolName = toolUse['name'] as String;
          final toolInput = toolUse['input'] as Map<String, dynamic>;
          final toolId = toolUse['id'] as String;

          log.fine('[AnthropicModel] Calling tool: $toolName');
          final result = await _callTool(toolName, toolInput);

          toolResults.add(
            anthropic.Block.toolResult(
              toolUseId: toolId,
              content: anthropic.ToolResultBlockContent.text(
                jsonEncode(result),
              ),
            ),
          );

          log.finer('[AnthropicModel] Tool result: $toolName = $result');
        } on Exception catch (e) {
          final toolName = toolUse['name'] as String;
          final toolId = toolUse['id'] as String;

          log.severe('[AnthropicModel] Error calling tool $toolName: $e');
          toolResults.add(
            anthropic.Block.toolResult(
              toolUseId: toolId,
              content: anthropic.ToolResultBlockContent.text(
                jsonEncode({'error': e.toString()}),
              ),
            ),
          );
        }
      }

      // Add tool results to message history for next iteration
      currentMessages = [
        ...currentMessages,
        anthropic.Message(
          role: anthropic.MessageRole.user,
          content: anthropic.MessageContent.blocks(toolResults),
        ),
      ];
    }

    // Yield final response with complete message history
    final finalMessages = [
      ...originalMessages,
      Message.user([TextPart(prompt), ...attachments]),
      Message.model([TextPart(responseBuffer.toString())]),
    ];

    yield AgentResponse(output: '', messages: finalMessages);
  }

  /// Calls a tool with the given arguments.
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
              : await tool.onCall(args);
    } on Exception catch (ex) {
      // if the tool call throws an error, return the exception message
      result = {'error': ex.toString()};
    }

    log.fine('Tool: $name($args)= $result');
    return result;
  }

  /// Converts dartantic Tool objects to Anthropic API tool format.
  List<anthropic.Tool> _convertTools(List<Tool> tools) =>
      tools
          .map(
            (tool) => anthropic.Tool.custom(
              name: tool.name,
              description: tool.description ?? '',
              inputSchema:
                  tool.inputSchema?.toMap() ??
                  {'type': 'object', 'properties': {}},
            ),
          )
          .toList();

  @override
  Future<Float64List> createEmbedding(
    String text, {
    EmbeddingType type = EmbeddingType.document,
    int? dimensions,
  }) async {
    // Anthropic doesn't provide embeddings API
    throw UnsupportedError('Anthropic does not provide embeddings API');
  }

  /// Converts dartantic messages to Anthropic messages.
  List<anthropic.Message> _convertMessages(Iterable<Message> messages) =>
      messages.map((message) {
        final content = anthropic.MessageContent.blocks(
          message.parts.map(_convertPart).toList(),
        );

        return anthropic.Message(
          role:
              message.role == MessageRole.user
                  ? anthropic.MessageRole.user
                  : anthropic.MessageRole.assistant,
          content: content,
        );
      }).toList();

  /// Converts a dartantic Part to an Anthropic Block.
  anthropic.Block _convertPart(Part part) {
    if (part is TextPart) {
      return anthropic.Block.text(text: part.text);
    } else if (part is DataPart) {
      if (part.mimeType.startsWith('image/')) {
        return anthropic.Block.image(
          source: anthropic.ImageBlockSource(
            type: anthropic.ImageBlockSourceType.base64,
            mediaType: _getImageMediaType(part.mimeType),
            data: base64Encode(part.bytes),
          ),
        );
      } else {
        // For non-image data, include as text
        return anthropic.Block.text(text: 'Data: ${part.mimeType}');
      }
    } else if (part is LinkPart) {
      return anthropic.Block.text(text: 'Link: ${part.url}');
    } else if (part is ToolPart) {
      if (part.kind == ToolPartKind.call) {
        return anthropic.Block.toolUse(
          id: part.id,
          name: part.name,
          input: part.arguments,
        );
      } else {
        return anthropic.Block.toolResult(
          toolUseId: part.id,
          content: anthropic.ToolResultBlockContent.text(
            jsonEncode(part.result),
          ),
        );
      }
    }
    return anthropic.Block.text(text: part.toString());
  }

  /// Gets the image media type for Anthropic API.
  anthropic.ImageBlockSourceMediaType _getImageMediaType(String mimeType) {
    switch (mimeType) {
      case 'image/jpeg':
      case 'image/jpg':
        return anthropic.ImageBlockSourceMediaType.imageJpeg;
      case 'image/png':
        return anthropic.ImageBlockSourceMediaType.imagePng;
      case 'image/gif':
        return anthropic.ImageBlockSourceMediaType.imageGif;
      case 'image/webp':
        return anthropic.ImageBlockSourceMediaType.imageWebp;
      default:
        return anthropic.ImageBlockSourceMediaType.imageJpeg;
    }
  }
}
