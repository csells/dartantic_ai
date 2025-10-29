// ignore_for_file: avoid_print

// Test script to verify Mistral usage tracking with updated mistralai_dart
// This tests the fix for the workaround in mistral_chat_model.dart

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

Future<void> main() async {
  // Create agent with Mistral
  final agent = Agent('mistral:mistral-small-latest');

  print('Testing Mistral with usage tracking in streaming...\n');

  // Send a simple message and verify usage is tracked
  final result = await agent.send('Say hello in exactly 10 words.');

  print('Response: ${result.output}');
  print('Usage: ${result.usage}');
  print('  - Prompt tokens: ${result.usage?.promptTokens}');
  print('  - Response tokens: ${result.usage?.responseTokens}');
  print('  - Total tokens: ${result.usage?.totalTokens}');

  if (result.usage != null &&
      result.usage!.promptTokens != null &&
      result.usage!.responseTokens != null) {
    print('\n✓ Mistral usage tracking test completed successfully!');
    print(
      '  The native mistralai_dart API now includes usage field '
      '(no HTTP workaround needed).',
    );
  } else {
    print('\n✗ ERROR: Usage tracking failed!');
    exit(1);
  }

  exit(0);
}
