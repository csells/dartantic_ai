import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

/// Logger for chat.mappers.llama_cpp operations.
final Logger _logger = Logger('dartantic.chat.mappers.llama_cpp');

/// Extension on [List<ChatMessage>] to convert messages to text prompt.
extension MessageListMapper on List<ChatMessage> {
  /// Converts this list of [ChatMessage]s to a text prompt string.
  ///
  /// LlamaCpp uses text-based prompts with formatting handled by ChatFormat,
  /// so we concatenate messages into a single text prompt.
  String toPrompt() {
    _logger.fine('Converting $length messages to LlamaCpp prompt');

    final buffer = StringBuffer();
    for (final message in this) {
      switch (message.role) {
        case ChatMessageRole.system:
          buffer.writeln('System: ${_extractTextContent(message)}');
        case ChatMessageRole.user:
          buffer.writeln('User: ${_extractTextContent(message)}');
        case ChatMessageRole.model:
          buffer.writeln('Assistant: ${_extractTextContent(message)}');
      }
    }

    return buffer.toString().trim();
  }

  String _extractTextContent(ChatMessage message) => message.parts.text;
}

/// Helper class to convert LlamaCpp text responses to ChatResult.
class ChatResultMapper {
  /// Creates a new ChatResultMapper.
  ChatResultMapper(this.text, {this.isDone = false});

  /// The text content from LlamaCpp.
  final String text;

  /// Whether this is the final chunk.
  final bool isDone;

  /// Converts this text response to a [ChatResult].
  ChatResult<ChatMessage> toChatResult() {
    _logger.fine('Converting LlamaCpp response to ChatResult (done: $isDone)');

    final parts = <Part>[];
    if (text.isNotEmpty) {
      parts.add(TextPart(text));
    }

    final responseMessage = ChatMessage(
      role: ChatMessageRole.model,
      parts: parts,
    );

    return ChatResult<ChatMessage>(
      output: responseMessage,
      messages: [responseMessage],
      finishReason: isDone ? FinishReason.stop : FinishReason.unspecified,
      metadata: {'done': isDone},
    );
  }
}
