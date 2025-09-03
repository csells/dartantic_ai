// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main() async {
  print('=== Single Tool Call Example ===\n');

  final agent = Agent('anthropic', tools: [weatherTool]);
  // final agent = Agent('openai-responses', tools: [weatherTool]);
  const prompt = 'What is the weather in Boston?';
  final response = await agent.send(prompt);
  print('User: $prompt');
  print('Assistant: ${response.output}\n');
  dumpMessages(response.messages);

  exit(0);
}
