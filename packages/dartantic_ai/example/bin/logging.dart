// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:logging/logging.dart';

void main() async {
  if (Platform.environment.containsKey('DARTANTIC_LOG_LEVEL')) {
    await envLogging();
  }

  await defaultLogging();
  await levelFiltering();
  await providerFiltering();
  await customHandlers();
  exit(0);
}

Future<void> envLogging() async {
  print('\nEnvironment Logging');
  final level = Platform.environment['DARTANTIC_LOG_LEVEL']!;
  print('DARTANTIC_LOG_LEVEL = $level');

  final agent = Agent('openai');
  const prompt = 'Hello! Just say hi back.';
  final result = await agent.send(prompt);

  print('User: $prompt');
  print('${agent.displayName}: ${result.output}');
}

Future<void> defaultLogging() async {
  print('\nDefault Logging');
  Agent.loggingOptions = const LoggingOptions();

  final agent = Agent('openai');
  const prompt = 'Hello! Just say hi back.';
  final result = await agent.send(prompt);

  print('User: $prompt');
  print('${agent.displayName}: ${result.output}');
}

Future<void> levelFiltering() async {
  print('\nLevel Filtering');
  Agent.loggingOptions = const LoggingOptions(level: Level.FINE);

  final agent = Agent('openai');
  const prompt = 'Quick test';
  final result = await agent.send(prompt);
  print('User: $prompt');
  print('${agent.displayName}: ${result.output}');
}

Future<void> providerFiltering() async {
  print('\nProvider Filtering');
  Agent.loggingOptions = const LoggingOptions(filter: 'openai');

  final openaiAgent = Agent('openai');
  final result = await openaiAgent.send('Test OpenAI');
  print('User: Test OpenAI');
  print('${openaiAgent.displayName}: ${result.output}');
}

Future<void> customHandlers() async {
  print('\nCustom Handlers');
  const color = '\x1B[31m'; // Red
  Agent.loggingOptions = LoggingOptions(
    onRecord: (record) {
      final component = record.loggerName.split('.').last;
      print('$color[$component] ${record.message}\x1B[0m');
    },
  );

  final agent = Agent('openai');
  final result = await agent.send('Show me colors!');
  print('User: Show me colors!');
  print('${agent.displayName}: ${result.output}');
}
