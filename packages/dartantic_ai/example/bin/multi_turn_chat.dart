import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/src/dump_stuff.dart';

void main() async {
  const model = 'openai-responses';
  await multiTurnChat(model);
  await multiTurnChatStream(model);
  exit(0);
}

Future<void> multiTurnChat(String model) async {
  stdout.writeln('\n## Multi-Turn Chat');

  final agent = Agent(model);
  final messages = <ChatMessage>[];

  const prompt1 = 'My name is Alice.';
  stdout.writeln('User: $prompt1');
  final response1 = await agent.send(prompt1, history: messages);
  messages.addAll(response1.messages);
  stdout.writeln('${agent.displayName}: ${response1.output}\n');

  const prompt2 = 'What is my name?';
  stdout.writeln('User: $prompt2');
  final response2 = await agent.send(prompt2, history: messages);
  messages.addAll(response2.messages);
  stdout.writeln('${agent.displayName}: ${response2.output}\n');

  dumpMessages(messages);
}

Future<void> multiTurnChatStream(String model) async {
  final agent = Agent(model);
  final messages = <ChatMessage>[];

  stdout.writeln('\n## Multi-Turn Chat Streaming');

  const prompt1 = 'My name is Alice.';
  stdout.writeln('User: $prompt1');
  stdout.write('${agent.displayName}: ');
  await for (final chunk in agent.sendStream(prompt1)) {
    stdout.write(chunk.output);
    messages.addAll(chunk.messages);
  }
  stdout.writeln();

  const prompt2 = 'What is my name?';
  stdout.writeln('User: $prompt2');
  stdout.write('${agent.displayName}: ');
  // Pass a copy of messages as history to avoid mutation issues
  final history = List<ChatMessage>.from(messages);
  await for (final chunk in agent.sendStream(prompt2, history: history)) {
    stdout.write(chunk.output);
    messages.addAll(chunk.messages);
  }
  stdout.writeln();

  dumpMessages(messages);
}
