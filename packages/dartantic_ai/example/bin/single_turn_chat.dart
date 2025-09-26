// ignore_for_file: avoid_print, unused_local_variable

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

void main() async {
  final agent = Agent('openai-responses');

  const prompt1 = 'What is the capital of England?';
  print('\nnon-streaming example: $prompt1');
  final response = await agent.send(prompt1);
  print(response.output);

  const prompt2 = 'Count from 1 to 5, one number at a time';
  print('\nstreaming example: $prompt2');
  await for (final chunk in agent.sendStream(prompt2)) {
    stdout.write(chunk.output);
  }
  print('\n');

  exit(0);
}
