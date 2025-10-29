import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/src/dump_stuff.dart';

void main() async {
  // Enable thinking output with Claude Sonnet 4.5 or GPT-5
  final agent = Agent(
    'anthropic:claude-sonnet-4-5',
    chatModelOptions: const AnthropicChatOptions(
      maxTokens: 16000,
      thinking: ThinkingConfig.enabled(
        type: ThinkingConfigEnabledType.enabled,
        budgetTokens: 10000,
      ),
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

  // Thinking metadata is in result.metadata (not in message metadata)
  final thinking = result.metadata['thinking'];
  assert(thinking is String && thinking.isNotEmpty);
  stdout.writeln('[[$thinking]]\n');
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
  exit(0);
}
