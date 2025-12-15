import 'package:dartantic_ai/dartantic_ai.dart';

/// Tracks a single message in the REPL conversation history.
///
/// Each entry contains the message and optional metadata about the model
/// that generated it (for model responses).
class HistoryEntry {
  /// Creates a history entry for a message.
  HistoryEntry({
    required this.message,
    this.modelName = '',
  });

  /// The chat message.
  final ChatMessage message;

  /// The model name that generated this message (for model messages only).
  ///
  /// Empty string for user messages and system messages.
  final String modelName;
}
