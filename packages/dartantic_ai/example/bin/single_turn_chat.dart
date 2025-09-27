import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

void main() async {
  const model = 'openai-responses';
  await singleTurnChat(model);
  await singleTurnChatStream(model);
  exit(0);
}

Future<void> singleTurnChat(String model) async {
  stdout.writeln('\n## Single Turn Chat');

  final agent = Agent(model);
  const prompt = 'What is the capital of England?';
  stdout.writeln('User: $prompt');
  final response = await agent.send(prompt);
  stdout.writeln('${agent.displayName}: ${response.output}');
  dumpMessages(response.messages);
}

Future<void> singleTurnChatStream(String model) async {
  stdout.writeln('\n## Single Turn Chat Streaming');

  final agent = Agent(model);
  final history = <ChatMessage>[];
  const prompt = 'Count from 1 to 5, one number at a time';
  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  }
  stdout.writeln();
  dumpMessages(history);
}
