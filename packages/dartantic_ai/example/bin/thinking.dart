import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/src/dump_stuff.dart';

void main() async {
  final agent = Agent('openai-responses:gpt-5', enableThinking: true);
  stdout.writeln('[[model thinking appears in brackets]]\n');
  await thinking(agent);
  await thinkingStream(agent);
  exit(0);
}

Future<void> thinking(Agent agent) async {
  stdout.writeln('\n${agent.displayName} thinking:');
  final result = await agent.send('In one sentence: how does quicksort work?');

  // Thinking is in result.thinking
  final thinking = result.thinking;
  assert(thinking != null && thinking.isNotEmpty);
  stdout.writeln('[[$thinking]]\n');
  stdout.writeln(result.output);
  dumpMessages(result.messages);
}

Future<void> thinkingStream(Agent agent) async {
  stdout.writeln('\n${agent.displayName} thinkingStream:');

  final history = <ChatMessage>[];
  var stillThinking = true;
  stdout.write('[[');

  final thinkingBuffer = StringBuffer();
  await for (final chunk in agent.sendStream(
    'In one sentence: how does quicksort work?',
  )) {
    // Check for thinking in the ChatResult
    final thinking = chunk.thinking;
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
  exit(0);
}
