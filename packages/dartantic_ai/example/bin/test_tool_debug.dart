// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';
import 'package:logging/logging.dart';

void main() async {
  // Enable detailed logging
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print(
      '${record.level.name}: ${record.time}: ${record.loggerName}: '
      '${record.message}',
    );
  });

  final agent = Agent('openai-responses', tools: [weatherTool]);
  const prompt = 'What is the weather in Boston?';
  print('\nsingle tool call: $prompt');
  final response = await agent.send(prompt);
  print(response.output);
  dumpMessages(response.messages);

  exit(0);
}
