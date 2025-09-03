// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';

void main() async {
  print('=== Debug Tool Result IDs ===\n');

  // Create the model directly
  final provider = Providers.get('openai-responses');
  final model = provider.createChatModel(tools: []);
  
  // Test sending a tool result manually
  final messages = [
    const ChatMessage(
      role: ChatMessageRole.user,
      parts: [TextPart('Test user message')],
    ),
    const ChatMessage(
      role: ChatMessageRole.model,
      parts: [
        ToolPart.call(
          id: 'call_test123',
          name: 'weather',
          arguments: {'location': 'Boston'},
        ),
      ],
    ),
    const ChatMessage(
      role: ChatMessageRole.user,
      parts: [
        ToolPart.result(
          id: 'call_test123', // Use same ID
          name: 'weather',
          result: '{"temperature": 25, "conditions": "sunny"}',
        ),
      ],
    ),
  ];
  
  print('Testing with tool result message...');
  try {
    await for (final result in model.sendStream(messages)) {
      print('Result: ${result.output}');
      if (result.finishReason == FinishReason.stop) {
        break;
      }
    }
  } catch (e) {
    print('Error: $e');
  }

  exit(0);
}