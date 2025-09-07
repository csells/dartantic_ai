// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

Future<void> main() async {
  print('Testing Code Interpreter...\n');

  final agent = Agent(
    'openai-responses:gpt-4o',
    chatModelOptions: const OpenAIResponsesChatOptions(
      serverSideTools: {OpenAIServerSideTool.codeInterpreter},
    ),
  );

  const prompt = 'Calculate 2 + 2 using Python code';

  print('Prompt: $prompt\n');
  print('Response:\n');

  try {
    await for (final chunk in agent.sendStream(prompt)) {
      if (chunk.output.isNotEmpty) stdout.write(chunk.output);

      final ci = chunk.metadata['code_interpreter'];
      if (ci != null) {
        // ignore: avoid_dynamic_calls
        print('\n[code_interpreter/${ci['stage']}]');
      }
    }
    print('\nSuccess!');
  } on Exception catch (e) {
    print('\nError: $e');
  }
}
