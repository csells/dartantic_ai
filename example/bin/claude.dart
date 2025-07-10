// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/time_tool_call.dart';

void main() async {
  // Create an agent using the Anthropic provider
  final agent = Agent(
    'anthropic',
    systemPrompt:
        'You are Claude, a helpful AI assistant created by'
        ' Anthropic. Be concise and accurate.',
    tools: [
      Tool(
        name: 'time',
        description: 'Get the current time in a given time zone',
        inputSchema: TimeFunctionInput.schemaMap.toSchema(),
        onCall: onTimeCall,
      ),
    ],
  );

  print('🤖 Claude AI Assistant (powered by Anthropic)');
  print('Type your questions or "quit" to exit.\n');

  // Interactive chat loop
  while (true) {
    stdout.write('You: ');
    final input = stdin.readLineSync();

    if (input == null || input.trim().toLowerCase() == 'quit') {
      print('\nGoodbye! 👋');
      break;
    }

    if (input.trim().isEmpty) {
      continue;
    }

    try {
      print('\nClaude: ');

      // Stream the response for real-time output
      await for (final chunk in agent.runStream(input)) {
        stdout.write(chunk.output);
      }

      print('\n');
    } on Exception catch (e) {
      print('Error: $e');
      print(
        'Make sure you have set your ANTHROPIC_API_KEY environment variable.\n',
      );
    }
  }

  exit(0);
}
