import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:mistralai_dart/mistralai_dart.dart' as mistral;

import '../helpers/message_part_helpers.dart';

/// Logger for Mistral message mapping operations.
final Logger _logger = Logger('dartantic.chat.mappers.mistral');

/// Extension on [List<Tool>] to convert to Mistral tools.
extension ToolListMapper on List<Tool> {
  /// Converts this list of [Tool]s to a list of Mistral [Tool]s.
  List<mistral.Tool> toMistralTools() {
    _logger.fine('Converting $length tools to Mistral format');
    return map(
      (tool) => mistral.Tool(
        type: mistral.ToolType.function,
        function: mistral.FunctionDefinition(
          name: tool.name,
          description: tool.description,
          parameters: tool.inputSchema.schemaMap! as Map<String, dynamic>,
        ),
      ),
    ).toList(growable: false);
  }
}

/// Extension on [List<Message>] to convert messages to Mistral SDK
/// messages.
extension MessageListMapper on List<ChatMessage> {
  /// Converts this list of [ChatMessage]s to a list of Mistral SDK
  /// [mistral.ChatCompletionMessage]s.
  List<mistral.ChatCompletionMessage> toChatCompletionMessages() {
    _logger.fine('Converting $length messages to Mistral format');

    // Expand messages to handle multiple tool results
    final expandedMessages = <mistral.ChatCompletionMessage>[];
    for (final message in this) {
      if (message.role == ChatMessageRole.user) {
        // Check if this is a tool result message with multiple results
        final toolResults = message.parts.toolResults;
        if (toolResults.length > 1) {
          // Mistral requires separate tool messages for each result
          for (final toolResult in toolResults) {
            final content = ToolResultHelpers.serialize(toolResult.result);
            expandedMessages.add(
              mistral.ChatCompletionMessage(
                role: mistral.ChatCompletionMessageRole.tool,
                content: content,
                toolCallId: toolResult.id,
              ),
            );
          }
        } else {
          // Single result or regular message
          expandedMessages.add(_mapMessage(message));
        }
      } else {
        // Non-user messages are mapped normally
        expandedMessages.add(_mapMessage(message));
      }
    }

    return expandedMessages;
  }

  mistral.ChatCompletionMessage _mapMessage(ChatMessage message) {
    _logger.fine(
      'Mapping ${message.role.name} message with ${message.parts.length} parts',
    );
    switch (message.role) {
      case ChatMessageRole.system:
        return mistral.ChatCompletionMessage(
          role: mistral.ChatCompletionMessageRole.system,
          content: _extractTextContent(message),
        );
      case ChatMessageRole.user:
        // Check if this is a tool result message
        final toolResults = message.parts.toolResults;

        if (toolResults.isNotEmpty) {
          // Mistral expects separate tool messages for each result
          // This should be handled at a higher level, so here we just take
          // the first
          final toolResult = toolResults.first;
          final content = ToolResultHelpers.serialize(toolResult.result);
          return mistral.ChatCompletionMessage(
            role: mistral.ChatCompletionMessageRole.tool,
            content: content,
            toolCallId: toolResult.id,
          );
        }

        return mistral.ChatCompletionMessage(
          role: mistral.ChatCompletionMessageRole.user,
          content: _extractTextContent(message),
        );
      case ChatMessageRole.model:
        // Extract text content
        final textContent = _extractTextContent(message);

        // Extract tool calls
        final toolCalls = message.parts.toolCalls
            .map(
              (p) => mistral.ToolCall(
                id: p.id,
                type: mistral.ToolCallType.function,
                function: mistral.FunctionCall(
                  name: p.name,
                  arguments: json.encode(p.arguments ?? {}),
                ),
              ),
            )
            .toList();

        return mistral.ChatCompletionMessage(
          role: mistral.ChatCompletionMessageRole.assistant,
          content: textContent.isEmpty ? null : textContent,
          toolCalls: toolCalls.isEmpty ? null : toolCalls,
        );
    }
  }

  String _extractTextContent(ChatMessage message) {
    final content = message.parts.text;
    if (content.isEmpty) {
      _logger.fine('No text parts found in message');
      return '';
    }
    _logger.fine('Extracted text content: ${content.length} characters');
    return content;
  }
}

/// Extension on [mistral.ChatCompletionResponse] to convert to [ChatResult].
extension ChatResultMapper on mistral.ChatCompletionResponse {
  /// Converts this [mistral.ChatCompletionResponse] to a [ChatResult].
  ChatResult<ChatMessage> toChatResult() {
    final choice = choices.first;
    final content = choice.message.content ?? '';
    _logger.fine(
      'Converting Mistral response to ChatResult: id=$id, '
      'content=${content.length} characters',
    );

    // Extract tool calls from the response
    final toolCallParts =
        choice.message.toolCalls
            ?.where((tc) => tc.id != null && tc.function?.name != null)
            .map(
              (tc) => ToolPart.call(
                id: tc.id!,
                name: tc.function!.name!,
                arguments: tc.function!.arguments != null
                    ? json.decode(tc.function!.arguments!)
                        as Map<String, dynamic>
                    : {},
              ),
            )
            .toList() ??
        [];

    final parts = <Part>[
      if (content.isNotEmpty) TextPart(content),
      ...toolCallParts,
    ];

    final message = ChatMessage(role: ChatMessageRole.model, parts: parts);

    return ChatResult<ChatMessage>(
      id: id,
      output: message,
      messages: [message],
      finishReason: _mapFinishReason(choice.finishReason),
      metadata: {'model': model, 'created': created},
      usage: _mapUsage(usage),
    );
  }

  LanguageModelUsage _mapUsage(mistral.ChatCompletionUsage usage) {
    _logger.fine(
      'Mapping usage: prompt=${usage.promptTokens}, '
      'response=${usage.completionTokens}, total=${usage.totalTokens}',
    );
    return LanguageModelUsage(
      promptTokens: usage.promptTokens,
      responseTokens: usage.completionTokens,
      totalTokens: usage.totalTokens,
    );
  }
}

/// Mapper for [mistral.ChatCompletionStreamResponse].
extension CreateChatCompletionStreamResponseMapper
    on mistral.ChatCompletionStreamResponse {
  /// Converts a [mistral.ChatCompletionStreamResponse] to a [ChatResult].
  ChatResult<ChatMessage> toChatResult() {
    final choice = choices.first;
    final content = choice.delta.content ?? '';
    _logger.fine(
      'Converting Mistral stream response to ChatResult: id=$id, '
      'content=${content.length} characters',
    );

    // Extract tool calls from streaming delta
    // Note: Mistral sends complete tool calls, not incremental deltas
    final toolCallParts =
        choice.delta.toolCalls
            ?.where((tc) => tc.id != null && tc.function?.name != null)
            .map((tc) {
          final args = tc.function?.arguments;
          return ToolPart.call(
            id: tc.id!,
            name: tc.function!.name!,
            arguments: args != null && args.isNotEmpty
                ? json.decode(args) as Map<String, dynamic>
                : {},
          );
        }).toList() ??
        [];

    final parts = <Part>[
      if (content.isNotEmpty) TextPart(content),
      ...toolCallParts,
    ];

    final message = ChatMessage(role: ChatMessageRole.model, parts: parts);

    return ChatResult<ChatMessage>(
      id: id,
      output: message,
      messages: [message],
      finishReason: _mapFinishReason(choice.finishReason),
      metadata: {'model': model, 'created': created},
      usage: usage != null ? _mapUsage(usage!) : null,
    );
  }

  LanguageModelUsage _mapUsage(mistral.ChatCompletionUsage usage) {
    _logger.fine(
      'Mapping stream usage: prompt=${usage.promptTokens}, '
      'response=${usage.completionTokens}, total=${usage.totalTokens}',
    );
    return LanguageModelUsage(
      promptTokens: usage.promptTokens,
      responseTokens: usage.completionTokens,
      totalTokens: usage.totalTokens,
    );
  }
}

FinishReason _mapFinishReason(mistral.ChatCompletionFinishReason? reason) {
  final mapped = switch (reason) {
    mistral.ChatCompletionFinishReason.stop => FinishReason.stop,
    mistral.ChatCompletionFinishReason.length => FinishReason.length,
    mistral.ChatCompletionFinishReason.modelLength => FinishReason.length,
    mistral.ChatCompletionFinishReason.error => FinishReason.unspecified,
    mistral.ChatCompletionFinishReason.toolCalls => FinishReason.toolCalls,
    null => FinishReason.unspecified,
  };
  _logger.fine('Mapped finish reason: $reason -> $mapped');
  return mapped;
}
