import 'package:dartantic_interface/dartantic_interface.dart';

/// Accumulates streaming chat results into a final consolidated result.
///
/// Handles accumulation of output text, messages, metadata (including
/// thinking), and usage statistics from streaming chunks into a final
/// ChatResult.
class AgentResponseAccumulator {
  /// Creates a new response accumulator.
  AgentResponseAccumulator();

  final List<ChatMessage> _allNewMessages = <ChatMessage>[];
  final StringBuffer _finalOutputBuffer = StringBuffer();
  final StringBuffer _thinkingBuffer = StringBuffer();
  final Map<String, dynamic> _accumulatedMetadata = <String, dynamic>{};

  ChatResult<String> _finalResult = ChatResult<String>(
    output: '',
    finishReason: FinishReason.unspecified,
    metadata: const <String, dynamic>{},
    usage: null,
  );

  /// Adds a streaming result chunk to the accumulator.
  void add(ChatResult<String> result) {
    // Accumulate output text
    if (result.output.isNotEmpty) {
      _finalOutputBuffer.write(result.output);
    }

    // Accumulate messages
    _allNewMessages.addAll(result.messages);

    // Store the latest result for final metadata/usage/finishReason
    _finalResult = result;

    // Accumulate thinking from streaming chunks
    if (result.thinking != null && result.thinking!.isNotEmpty) {
      _thinkingBuffer.write(result.thinking);
    }

    // Merge metadata (preserving response-level info from final chunk)
    for (final entry in result.metadata.entries) {
      _accumulatedMetadata[entry.key] = entry.value;
    }
  }

  /// Builds the final accumulated ChatResult.
  ChatResult<String> buildFinal() {
    final thinking = _thinkingBuffer.isNotEmpty
        ? _thinkingBuffer.toString()
        : null;

    return ChatResult<String>(
      id: _finalResult.id,
      output: _finalOutputBuffer.toString(),
      messages: _allNewMessages,
      thinking: thinking,
      finishReason: _finalResult.finishReason,
      metadata: _accumulatedMetadata,
      usage: _finalResult.usage,
    );
  }
}
