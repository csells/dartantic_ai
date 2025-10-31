import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:ollama_dart/ollama_dart.dart' as o;

import '../helpers/message_part_helpers.dart';
import '../helpers/tool_id_helpers.dart';
import 'ollama_chat_options.dart';

/// Logger for chat.mappers.ollama operations.
final Logger _logger = Logger('dartantic.chat.mappers.ollama');

/// Creates a [o.GenerateChatCompletionRequest] from the given input.
o.GenerateChatCompletionRequest generateChatCompletionRequest(
  List<ChatMessage> messages, {
  required String modelName,
  required OllamaChatOptions? options,
  required OllamaChatOptions defaultOptions,
  List<Tool>? tools,
  double? temperature,
  JsonSchema? outputSchema,
}) {
  _logger.fine(
    'Creating Ollama chat completion request for model: $modelName '
    'with ${messages.length} messages',
  );

  // Use native Ollama format parameter for structured output
  final format = outputSchema != null
      ? o.GenerateChatCompletionRequestFormat.schema(
          Map<String, dynamic>.from(outputSchema.schemaMap ?? {}),
        )
      : options?.format ?? defaultOptions.format;

  return o.GenerateChatCompletionRequest(
    model: modelName,
    messages: messages.toMessages(),
    format: format,
    keepAlive: options?.keepAlive ?? defaultOptions.keepAlive,
    tools: tools?.toOllamaTools(),
    stream: true,
    options: o.RequestOptions(
      numKeep: options?.numKeep ?? defaultOptions.numKeep,
      seed: options?.seed ?? defaultOptions.seed,
      numPredict: options?.numPredict ?? defaultOptions.numPredict,
      topK: options?.topK ?? defaultOptions.topK,
      topP: options?.topP ?? defaultOptions.topP,
      minP: options?.minP ?? defaultOptions.minP,
      tfsZ: options?.tfsZ ?? defaultOptions.tfsZ,
      typicalP: options?.typicalP ?? defaultOptions.typicalP,
      repeatLastN: options?.repeatLastN ?? defaultOptions.repeatLastN,
      temperature: temperature,
      repeatPenalty: options?.repeatPenalty ?? defaultOptions.repeatPenalty,
      presencePenalty:
          options?.presencePenalty ?? defaultOptions.presencePenalty,
      frequencyPenalty:
          options?.frequencyPenalty ?? defaultOptions.frequencyPenalty,
      mirostat: options?.mirostat ?? defaultOptions.mirostat,
      mirostatTau: options?.mirostatTau ?? defaultOptions.mirostatTau,
      mirostatEta: options?.mirostatEta ?? defaultOptions.mirostatEta,
      penalizeNewline:
          options?.penalizeNewline ?? defaultOptions.penalizeNewline,
      stop: options?.stop ?? defaultOptions.stop,
      numa: options?.numa ?? defaultOptions.numa,
      numCtx: options?.numCtx ?? defaultOptions.numCtx,
      numBatch: options?.numBatch ?? defaultOptions.numBatch,
      numGpu: options?.numGpu ?? defaultOptions.numGpu,
      mainGpu: options?.mainGpu ?? defaultOptions.mainGpu,
      lowVram: options?.lowVram ?? defaultOptions.lowVram,
      f16Kv: options?.f16KV ?? defaultOptions.f16KV,
      logitsAll: options?.logitsAll ?? defaultOptions.logitsAll,
      vocabOnly: options?.vocabOnly ?? defaultOptions.vocabOnly,
      useMmap: options?.useMmap ?? defaultOptions.useMmap,
      useMlock: options?.useMlock ?? defaultOptions.useMlock,
      numThread: options?.numThread ?? defaultOptions.numThread,
    ),
  );
}

/// Extension on [List<Tool>] to convert to Ollama SDK tool list.
extension OllamaToolListMapper on List<Tool> {
  /// Converts this list of [o.Tool]s to a list of Ollama SDK [o.Tool]s.
  List<o.Tool> toOllamaTools() => map(
    (tool) => o.Tool(
      type: o.ToolType.function,
      function: o.ToolFunction(
        name: tool.name,
        description: tool.description,
        parameters: Map<String, dynamic>.from(tool.inputSchema.schemaMap ?? {}),
      ),
    ),
  ).toList(growable: false);
}

/// Extension on [List<Message>] to convert messages to Ollama SDK messages.
extension MessageListMapper on List<ChatMessage> {
  /// Converts this list of [ChatMessage]s to a list of Ollama SDK
  /// [o.Message]s.
  List<o.Message> toMessages() {
    _logger.fine('Converting $length messages to Ollama format');
    return map(_mapMessage).expand((msg) => msg).toList(growable: false);
  }

  List<o.Message> _mapMessage(ChatMessage message) {
    switch (message.role) {
      case ChatMessageRole.system:
        return [
          o.Message(
            role: o.MessageRole.system,
            content: _extractTextContent(message),
          ),
        ];
      case ChatMessageRole.user:
        // Check if this is a tool result message
        final toolResults = message.parts.toolResults;
        if (toolResults.isNotEmpty) {
          // Tool result message
          return toolResults
              .map(
                (p) => o.Message(
                  role: o.MessageRole.tool,
                  // ignore: avoid_dynamic_calls
                  content: ToolResultHelpers.serialize(p.result),
                ),
              )
              .toList();
        } else {
          return _mapUserMessage(message);
        }
      case ChatMessageRole.model:
        return _mapModelMessage(message);
    }
  }

  List<o.Message> _mapUserMessage(ChatMessage message) {
    final textParts = message.parts.whereType<TextPart>().toList();
    final dataParts = message.parts.whereType<DataPart>().toList();

    if (dataParts.isEmpty) {
      // Text-only message
      final text = message.parts.text;
      return [o.Message(role: o.MessageRole.user, content: text)];
    } else if (textParts.length == 1 && dataParts.isNotEmpty) {
      // Single text with images (Ollama's preferred format)
      return [
        o.Message(
          role: o.MessageRole.user,
          content: textParts.first.text,
          images: dataParts
              .map((p) => base64Encode(p.bytes))
              .toList(growable: false),
        ),
      ];
    } else {
      // Multiple parts - map each separately
      return message.parts
          .map((part) {
            if (part is TextPart) {
              return o.Message(role: o.MessageRole.user, content: part.text);
            } else if (part is DataPart) {
              return o.Message(
                role: o.MessageRole.user,
                content: base64Encode(part.bytes),
              );
            }
            return null;
          })
          .nonNulls
          .toList(growable: false);
    }
  }

  List<o.Message> _mapModelMessage(ChatMessage message) {
    final textContent = _extractTextContent(message);
    final toolCalls = message.parts.toolCalls;

    return [
      o.Message(
        role: o.MessageRole.assistant,
        content: textContent,
        toolCalls: toolCalls.isNotEmpty
            ? toolCalls
                  .map(
                    (p) => o.ToolCall(
                      function: o.ToolCallFunction(
                        name: p.name,
                        arguments: p.arguments ?? {},
                      ),
                    ),
                  )
                  .toList(growable: false)
            : null,
      ),
    ];
  }

  String _extractTextContent(ChatMessage message) => message.parts.text;
}

/// Extension on [o.GenerateChatCompletionResponse] to convert to [ChatResult].
extension ChatResultMapper on o.GenerateChatCompletionResponse {
  /// Converts this [o.GenerateChatCompletionResponse] to a [ChatResult].
  ChatResult<ChatMessage> toChatResult() {
    _logger.fine('Converting Ollama response to ChatResult');
    final parts = <Part>[];

    // Add text content
    if (message.content.isNotEmpty) {
      parts.add(TextPart(message.content));
    }

    // Add tool calls
    if (message.toolCalls != null) {
      for (var i = 0; i < message.toolCalls!.length; i++) {
        final toolCall = message.toolCalls![i];
        if (toolCall.function != null) {
          // Generate a unique ID for this tool call
          final toolId = ToolIdHelpers.generateToolCallId(
            toolName: toolCall.function!.name,
            providerHint: 'ollama',
            arguments: toolCall.function!.arguments,
            index: i,
          );
          _logger.fine(
            'Generated tool ID: $toolId for tool: ${toolCall.function!.name}',
          );
          parts.add(
            ToolPart.call(
              id: toolId,
              name: toolCall.function!.name,
              arguments: toolCall.function!.arguments,
            ),
          );
        }
      }
    }

    final responseMessage = ChatMessage(
      role: ChatMessageRole.model,
      parts: parts,
    );

    // Convert Ollama token counts to usage
    // Only provide usage when done=true (final chunk)
    final usage = done && (promptEvalCount != null || evalCount != null)
        ? LanguageModelUsage(
            promptTokens: promptEvalCount,
            responseTokens: evalCount,
            totalTokens: promptEvalCount != null && evalCount != null
                ? promptEvalCount! + evalCount!
                : promptEvalCount ?? evalCount,
          )
        : null;

    if (usage != null) {
      _logger.fine(
        'Ollama usage: ${usage.promptTokens}/${usage.responseTokens}/${usage.totalTokens}',
      );
    }

    return ChatResult<ChatMessage>(
      output: responseMessage,
      messages: [responseMessage],
      finishReason: FinishReason.unspecified,
      metadata: {
        'model': model,
        'created_at': createdAt,
        'done': done,
        'total_duration': totalDuration,
        'load_duration': loadDuration,
        'prompt_eval_count': promptEvalCount,
        'prompt_eval_duration': promptEvalDuration,
        'eval_count': evalCount,
        'eval_duration': evalDuration,
      },
      usage: usage,
    );
  }
}
