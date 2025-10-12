import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/src/dump_stuff.dart';

void main() async {
  const model = 'gemini';
  await multiTurnChat(model);
  await multiTurnChatStream(model);
  exit(0);
}

Future<void> multiTurnChat(String model) async {
  stdout.writeln('\n## Multi-Turn Chat');

  final agent = Agent(model);
  final history = <ChatMessage>[];

  const prompt1 = 'My name is Alice.';
  stdout.writeln('User: $prompt1');
  final response1 = await agent.send(prompt1, history: history);
  history.addAll(response1.messages);
  stdout.writeln('${agent.displayName}: ${response1.output}\n');

  const prompt2 = 'What is my name?';
  stdout.writeln('User: $prompt2');
  final response2 = await agent.send(prompt2, history: history);
  history.addAll(response2.messages);
  stdout.writeln('${agent.displayName}: ${response2.output}\n');

  dumpMessages(history);
}

Future<void> multiTurnChatStream(String model) async {
  stdout.writeln('\n## Multi-Turn Chat Streaming');

  final agent = Agent(model);
  final history = <ChatMessage>[];

  const prompt1 = 'My name is Alice.';
  stdout.writeln('User: $prompt1');
  stdout.write('${agent.displayName}: ');
  await for (final chunk in agent.sendStream(prompt1)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  }
  stdout.writeln();

  const prompt2 = 'What is my name?';
  stdout.writeln('User: $prompt2');
  stdout.write('${agent.displayName}: ');
  await for (final chunk in agent.sendStream(prompt2, history: history)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  }
  stdout.writeln();

  dumpMessages(history);
}
