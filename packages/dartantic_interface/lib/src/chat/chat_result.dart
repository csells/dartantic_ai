import '../model/model.dart';
import 'chat_message.dart';

/// Result returned by the Chat Model.
class ChatResult<T extends Object> extends LanguageModelResult<T> {
  /// Creates a new chat result instance.
  ChatResult({
    required super.output,
    super.finishReason = FinishReason.unspecified,
    super.metadata = const {},
    super.usage,
    this.messages = const [],
    this.thinking,
    super.id,
  });

  /// The new messages generated during this chat interaction.
  final List<ChatMessage> messages;

  /// Extended thinking (chain-of-thought reasoning) content from the model.
  ///
  /// When thinking is enabled, models can expose their internal reasoning
  /// process. This field contains:
  /// - **During streaming**: Incremental thinking deltas (partial text)
  /// - **Non-streaming**: Complete accumulated thinking text
  final String? thinking;

  @override
  String toString() =>
      '''
ChatResult{
  id: $id,
  output: $output,
  messages: $messages,
  thinking: ${thinking != null ? '${thinking!.length} chars' : 'null'},
  finishReason: $finishReason,
  metadata: $metadata,
  usage: $usage,
}''';
}
