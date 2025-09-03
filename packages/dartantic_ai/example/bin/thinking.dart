import 'dart:io';

import 'package:colorize/colorize.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/src/dump_stuff.dart';

// TODO: check thinking + Agent.send();

void main() async {
  stdout.writeln(Colorize('-> model thinking appears in italics\n')..italic());

  // enable thinking output
  final agent = Agent(
    'openai-responses',
    chatModelOptions: const OpenAIResponsesChatOptions(
      reasoningSummary: OpenAIReasoningSummary.detailed,
    ),
  );

  // Track phase transitions to add spacing between thinking and text
  const phaseNone = 0;
  const phaseThinking = 1;
  const phaseText = 2;
  var last = phaseNone;

  void separator() {
    // Two newlines for clear separation
    stdout.writeln();
    stdout.writeln();
  }

  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(
    'In one sentence: how does quicksort work?',
  )) {
    final thinkingDelta = chunk.metadata['thinking'] as String?;
    final hasThinking = thinkingDelta != null && thinkingDelta.isNotEmpty;
    final hasText = chunk.output.isNotEmpty;

    if (hasThinking && last == phaseText) separator();
    if (hasThinking) {
      stdout.write(Colorize(thinkingDelta)..italic());
      last = phaseThinking;
    }

    if (hasText && last == phaseThinking) separator();
    if (hasText) {
      stdout.write(chunk.output);
      last = phaseText;
    }

    history.addAll(chunk.messages);
  }
  stdout.writeln();
  stdout.writeln();

  dumpMessages(history);

  exit(0);
}
