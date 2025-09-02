import 'dart:io';

import 'package:colorize/colorize.dart';
import 'package:dartantic_ai/dartantic_ai.dart';

void main() async {
  // Enable verbose logging for OpenAI Responses to debug SSE and payload
  // Agent.loggingOptions = const LoggingOptions(
  //   level: Level.FINE,
  //   filter: 'openai_responses',
  // );
  stdout.writeln(Colorize('model thinking appears in italics')..italic());

  // enable thinking output
  final agent = Agent(
    'openai-responses',
    chatModelOptions: const OpenAIResponsesChatOptions(
      reasoningSummary: OpenAIReasoningSummary.detailed,
    ),
  );

  await for (final chunk in agent.sendStream(
    'In one sentence: how does quicksort work?',
  )) {
    // Stream thinking text, if present
    final thinkingDelta = chunk.metadata['thinking'] as String?;
    if (thinkingDelta != null) stdout.write(Colorize(thinkingDelta)..italic());

    // Stream response text
    if (chunk.output.isNotEmpty) stdout.write(chunk.output);
  }
  stdout.writeln();

  exit(0);
}
