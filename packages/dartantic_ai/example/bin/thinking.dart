import 'dart:io';

import 'package:colorize/colorize.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart' show ChatMessage;

void main() async {
  final agent = Agent(
    'openai-responses',
    chatModelOptions: const OpenAIResponsesChatOptions(
      reasoningEffort: OpenAIReasoningEffort.medium,
      reasoningSummary: OpenAIReasoningSummary.detailed,
    ),
  );

  final history = <ChatMessage>[];
  final textBuffer = StringBuffer();

  // Legend demonstrating the exact styles we use below
  stdout.writeln(Colorize('model thinking appears in italics')..italic());

  await for (final chunk in agent.sendStream(
    'In one paragraph: how does quicksort work? Think carefully.',
    history: history,
  )) {
    // Stream assistant text (bold)
    if (chunk.output.isNotEmpty) {
      textBuffer.write(chunk.output);
      stdout.write(chunk.output);
    }

    // Stream thinking deltas in metadata (if present)
    final thinkingDelta = chunk.metadata['thinking'];
    if (thinkingDelta is String && thinkingDelta.isNotEmpty) {
      final ital = Colorize('[thinking] $thinkingDelta')..italic();
      stdout.write('THINKING: $ital');
    }

    // Always collect new messages for history continuity
    history.addAll(chunk.messages);
  }
  stdout.writeln();

  exit(0);
}
