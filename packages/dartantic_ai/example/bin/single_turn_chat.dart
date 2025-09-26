// ignore_for_file: avoid_print, unused_local_variable

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

void main() async {
  const model = 'openai-responses';
  final agent = Agent(model);

  const prompt1 = 'What is the capital of England?';
  print('\n${agent.displayName} non-streaming example: $prompt1');
  final response = await agent.send(prompt1);
  print(response.output);
  dumpMessages(response.messages);

  final history = <ChatMessage>[];
  const prompt2 = 'Count from 1 to 5, one number at a time';
  print('\n${agent.displayName} streaming example: $prompt2');
  await for (final chunk in agent.sendStream(prompt2)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  }
  stdout.writeln();
  dumpMessages(history);

  exit(0);
}
