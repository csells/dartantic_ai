// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/src/example_tools.dart';

void main() async {
  // Example: Setting API keys programmatically via Agent.environment
  // By default, Agent.environment will be checked first and on platforms with
  // an environment (i.e. not web), the fallback will be Platform.environment,
  // so this code is unnecessary. But it does show how you can put stuff into
  // Agent.environment for environments that don't already have an environment
  // setup for your use, e.g. the web, taking API keys from a database, etc.
  //
  // Note: This example copies from Platform.environment to demonstrate the
  // feature while still working with your existing environment setup.
  Agent.environment['OPENAI_API_KEY'] = Platform.environment['OPENAI_API_KEY']!;

  final history = <ChatMessage>[];

  // agent 1
  final agent1 = Agent('google');
  const prompt1 =
      'Hi! My name is Alice and I work as a software engineer in Seattle. '
      'I love hiking and coffee.';
  stdout.writeln('User: $prompt1');
  stdout.write('${agent1.displayName} (${agent1.model}): ');
  await agent1.sendStream(prompt1, history: history).forEach((chunk) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  });
  stdout.writeln('\n');

  // agent 2
  final agent2 = Agent('anthropic');
  const prompt2 = 'What do you remember about me?';
  stdout.writeln('User: $prompt2');
  stdout.write('${agent2.displayName} (${agent2.model}): ');
  await agent2.sendStream(prompt2, history: history).forEach((chunk) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  });
  stdout.writeln('\n');

  // agent 3
  final agent3 = Agent('openai', tools: [weatherTool, temperatureTool]);
  const prompt3 = 'Can you check the weather where I live?';
  stdout.writeln('User: $prompt3');
  stdout.write('${agent3.displayName} (${agent3.model}): ');
  await agent3.sendStream(prompt3, history: history).forEach((chunk) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  });
  stdout.writeln('\n');

  // agent 4
  final agent4 = Agent('google:gemini-3-pro-preview');
  const prompt4 = 'What outdoor activities would you recommend for me?';
  stdout.writeln('User: $prompt4');
  stdout.write('${agent4.displayName} (${agent4.model}): ');
  await agent4.sendStream(prompt4, history: history).forEach((chunk) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  });
  stdout.writeln('\n');

  // agent 5
  final agent5 = Agent('openai-responses');
  const prompt5 = 'Can you summarize our conversation?';
  stdout.writeln('User: $prompt5');
  stdout.write('${agent5.displayName} (${agent5.model}): ');
  await agent5.sendStream(prompt5, history: history).forEach((chunk) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  });
  stdout.writeln('\n');
}
