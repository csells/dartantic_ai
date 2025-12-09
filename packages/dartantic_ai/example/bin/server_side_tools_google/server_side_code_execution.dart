// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main(List<String> args) async {
  stdout.writeln('Google Server-Side Code Execution Demo\n');

  final agent = Agent(
    'google',
    chatModelOptions: const GoogleChatModelOptions(
      serverSideTools: {GoogleServerSideTool.codeExecution},
    ),
  );

  // First prompt: Calculate Fibonacci numbers and create CSV
  stdout.writeln('\n=== Step 1: Calculate Fibonacci Numbers ===');

  const prompt1 =
      'Calculate the first 10 Fibonacci numbers and store them in a variable '
      'called "fib_sequence". Then create a CSV file called "fibonacci.csv" '
      'with two columns: index and value. Show me the CSV content.';

  stdout.writeln('User: $prompt1');
  stdout.write('${agent.displayName}: ');

  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(prompt1)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
    // dumpMetadata(chunk.metadata, prefix: '\n');
  }
  stdout.writeln();

  // Second prompt: Calculate golden ratio and create plot
  stdout.writeln('\n=== Step 2: Calculate Golden Ratio ===');

  const prompt2 =
      'Using the fib_sequence variable we created earlier, calculate the '
      'golden ratio by dividing consecutive terms (skipping the first term, '
      'since it is 0). Create a plot showing how the ratio converges to the '
      'golden ratio (approximately 1.618). Save the plot as a PNG file called '
      '"golden_ratio.png" and show me the plot.';

  stdout.writeln('User: $prompt2');
  stdout.write('${agent.displayName}: ');

  await for (final chunk in agent.sendStream(prompt2, history: history)) {
    stdout.write(chunk.output);
    history.addAll(chunk.messages);
    // dumpMetadata(chunk.metadata, prefix: '\n');
  }
  stdout.writeln();

  dumpAssetsFromHistory(history, 'tmp');
  dumpMessages(history);
  exit(0);
}
