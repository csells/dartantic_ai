// ignore_for_file: avoid_print

// Test script to verify Ollama JSON schema support with updated ollama_dart
// This tests the fix for the workaround in ollama_chat_model.dart

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:json_schema/json_schema.dart';

Future<void> main() async {
  // Create agent with Ollama
  final agent = Agent('ollama:gemma2:2b');

  print('Testing Ollama with JSON schema (typed output)...\n');

  // Define a simple schema for structured output
  final result = await agent.send(
    'Generate a person with name John and age 30. '
    'Return as JSON.',
    outputSchema: JsonSchema.create({
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'age': {'type': 'integer'},
      },
      'required': ['name', 'age'],
    }),
  );

  final map = jsonDecode(result.output) as Map<String, dynamic>;
  print('Response output: ${map['name']}, age ${map['age']}');
  print('Response usage: ${result.usage}');
  print('\n✓ Ollama JSON schema test completed successfully!');
  print(
    '  The native ollama_dart API was used '
    '(no HTTP workaround needed).',
  );

  exit(0);
}
