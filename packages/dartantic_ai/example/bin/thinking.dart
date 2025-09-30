import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/src/dump_stuff.dart';

void main() async {
  // enable thinking output with gpt-5
  final agent = Agent(
    'openai-responses:gpt-5',
    chatModelOptions: const OpenAIResponsesChatModelOptions(
      reasoningSummary: OpenAIReasoningSummary.detailed,
    ),
  );

  stdout.writeln('[[model thinking appears in brackets]]\n');
  await thinking(agent);
  await thinkingStream(agent);
  exit(0);
}

Future<void> thinking(Agent agent) async {
  stdout.writeln('\nthinking:');
  final result = await agent.send('In one sentence: how does quicksort work?');
  // Thinking metadata is now consistently in result.metadata
  final thinking = result.metadata['thinking'];
  if (thinking is String && thinking.isNotEmpty) {
    // Verify it's also in the message for backwards compatibility
    assert(result.messages.last.metadata['thinking'] == thinking);
    stdout.writeln('[[$thinking]]\n');
  }
  stdout.writeln(result.output);
  dumpMessages(result.messages);
}

Future<void> thinkingStream(Agent agent) async {
  stdout.writeln('\nthinkingStream:');

  final history = <ChatMessage>[];
  var stillThinking = true;
  stdout.write('[[');

  final thinkingBuffer = StringBuffer();
  await for (final chunk in agent.sendStream(
    'In one sentence: how does quicksort work?',
  )) {
    // Check for thinking in the ChatResult metadata (not message metadata)
    final thinking = chunk.metadata['thinking'] as String?;
    final hasThinking = thinking != null && thinking.isNotEmpty;
    final hasText = chunk.output.isNotEmpty;

    if (hasThinking) {
      thinkingBuffer.write(thinking);
      stdout.write(thinking);
    }

    if (hasText) {
      if (stillThinking) {
        stillThinking = false;
        stdout.writeln(']]\n');
      }
      stdout.write(chunk.output);
    }

    history.addAll(chunk.messages);
  }

  stdout.writeln('\n');
  dumpMessages(history);
  assert(thinkingBuffer.toString() == history.last.metadata['thinking']);
  exit(0);
}
