import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:mistralai_dart/mistralai_dart.dart';

/// Logger for Mistral message mapping operations.
final Logger _logger = Logger('dartantic.chat.mappers.mistral');

/// Extension on [List<Message>] to convert messages to Mistral SDK
/// messages.
extension MessageListMapper on List<ChatMessage> {
  /// Converts this list of [ChatMessage]s to a list of Mistral SDK
  /// [ChatCompletionMessage]s.
  List<ChatCompletionMessage> toChatCompletionMessages() {
    _logger.fine('Converting $length messages to Mistral format');
    return map(_mapMessage).toList(growable: false);
  }

  ChatCompletionMessage _mapMessage(ChatMessage message) {
    _logger.fine(
      'Mapping ${message.role.name} message with ${message.parts.length} parts',
    );
    switch (message.role) {
      case ChatMessageRole.system:
        return ChatCompletionMessage(
          role: ChatCompletionMessageRole.system,
          content: _extractTextContent(message),
        );
      case ChatMessageRole.user:
        return ChatCompletionMessage(
          role: ChatCompletionMessageRole.user,
          content: _extractTextContent(message),
        );
      case ChatMessageRole.model:
        // Check for tool calls
        final toolCalls = message.parts.toolCalls;
        final toolResults = message.parts.toolResults;
        if (toolCalls.isNotEmpty || toolResults.isNotEmpty) {
          _logger.warning(
            'Mistral AI does not support tool calls, '
            'found ${toolCalls.length} tool calls and ${toolResults.length} '
            'tool results',
          );
          throw UnsupportedError('Mistral AI does not support tool calls');
        }

        return ChatCompletionMessage(
          role: ChatCompletionMessageRole.assistant,
          content: _extractTextContent(message),
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

/// Extension on [ChatCompletionResponse] to convert to [ChatResult].
extension ChatResultMapper on ChatCompletionResponse {
  /// Converts this [ChatCompletionResponse] to a [ChatResult].
  ChatResult<ChatMessage> toChatResult() {
    final choice = choices.first;
    final content = choice.message.content ?? '';
    _logger.fine(
      'Converting Mistral response to ChatResult: id=$id, '
      'content=${content.length} characters',
    );

    final message = ChatMessage(
      role: ChatMessageRole.model,
      parts: content.isNotEmpty ? [TextPart(content)] : [],
    );

    return ChatResult<ChatMessage>(
      id: id,
      output: message,
      messages: [message],
      finishReason: _mapFinishReason(choice.finishReason),
      metadata: {'model': model, 'created': created},
      usage: _mapUsage(usage),
    );
  }

  LanguageModelUsage _mapUsage(ChatCompletionUsage usage) {
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

/// Mapper for [ChatCompletionStreamResponse].
extension CreateChatCompletionStreamResponseMapper
    on ChatCompletionStreamResponse {
  /// Converts a [ChatCompletionStreamResponse] to a [ChatResult].
  ChatResult<ChatMessage> toChatResult() {
    final choice = choices.first;
    final content = choice.delta.content ?? '';
    _logger.fine(
      'Converting Mistral stream response to ChatResult: id=$id, '
      'content=${content.length} characters',
    );

    final message = ChatMessage(
      role: ChatMessageRole.model,
      parts: content.isNotEmpty ? [TextPart(content)] : [],
    );

    return ChatResult<ChatMessage>(
      id: id,
      output: message,
      messages: [message],
      finishReason: _mapFinishReason(choice.finishReason),
      metadata: {'model': model, 'created': created},
      usage: usage != null ? _mapUsage(usage!) : null,
    );
  }

  LanguageModelUsage _mapUsage(ChatCompletionUsage usage) {
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

FinishReason _mapFinishReason(ChatCompletionFinishReason? reason) {
  final mapped = switch (reason) {
    ChatCompletionFinishReason.stop => FinishReason.stop,
    ChatCompletionFinishReason.length => FinishReason.length,
    ChatCompletionFinishReason.modelLength => FinishReason.length,
    ChatCompletionFinishReason.error => FinishReason.unspecified,
    ChatCompletionFinishReason.toolCalls => FinishReason.toolCalls,
    null => FinishReason.unspecified,
  };
  _logger.fine('Mapped finish reason: $reason -> $mapped');
  return mapped;
}
