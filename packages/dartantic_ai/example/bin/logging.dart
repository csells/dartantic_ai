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
  await stringFiltering();
  await customHandlers();
  exit(0);
}

// set DARTANTIC_LOG_LEVEL environment variable to see output from this example
// e.g. `DARTANTIC_LOG_LEVEL=FINE dart example/bin/logging.dart`
Future<void> envLogging() async {
  print('\nEnvironment Logging');
  final level = Platform.environment['DARTANTIC_LOG_LEVEL']!;
  print('DARTANTIC_LOG_LEVEL = $level');

  final agent = Agent('gemini');
  const prompt = 'Hello! Just say hi back.';
  final result = await agent.send(prompt);

  print('User: $prompt');
  print('${agent.displayName}: ${result.output}');
}

Future<void> defaultLogging() async {
  print('\nDefault Logging');
  Agent.loggingOptions = const LoggingOptions();

  final agent = Agent('gemini');
  const prompt = 'Hello! Just say hi back.';
  final result = await agent.send(prompt);

  print('User: $prompt');
  print('${agent.displayName}: ${result.output}');
}

Future<void> levelFiltering() async {
  print('\nLevel Filtering');
  Agent.loggingOptions = const LoggingOptions(level: Level.FINE);

  final agent = Agent('gemini');
  const prompt = 'Quick test';
  final result = await agent.send(prompt);
  print('User: $prompt');
  print('${agent.displayName}: ${result.output}');
}

Future<void> stringFiltering() async {
  print('\nString Filtering');
  Agent.loggingOptions = const LoggingOptions(filter: 'google');

  final agent = Agent('gemini');
  const prompt = 'Hello!';
  final result = await agent.send(prompt);
  print('User: $prompt');
  print('${agent.displayName}: ${result.output}');
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

  final agent = Agent('gemini');
  final result = await agent.send('Show me colors!');
  print('User: Show me colors!');
  print('${agent.displayName}: ${result.output}');
}
