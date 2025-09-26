// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

void main() async {
  const model = 'openai-responses';
  final agent = Agent(model, tools: [weatherTool]);
  const prompt = 'What is the weather in Boston?';
  print('\n${agent.displayName} single tool call: $prompt');
  final response = await agent.send(prompt);
  print(response.output);
  dumpMessages(response.messages);

  final history = <ChatMessage>[];
  print('\n${agent.displayName} single tool call streaming: $prompt');
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
  }
  stdout.writeln();
  dumpMessages(history);

  exit(0);
}
