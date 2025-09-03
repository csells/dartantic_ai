// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';

// Simple weather tool for testing
final weatherTool = Tool<Map<String, dynamic>>(
  name: 'weather',
  description: 'Get the weather for a given location',
  inputSchema: JsonSchema.create({
    'type': 'object',
    'properties': {
      'location': {
        'type': 'string',
        'description': 'The location to get the weather for',
      },
    },
    'required': ['location'],
  }),
  onCall: (input) {
    final location = input['location'] as String;
    final temp = 20 + Random().nextInt(15);
    return {
      'location': location,
      'temperature': temp,
      'unit': 'C',
      'conditions': ['sunny', 'cloudy', 'rainy'][Random().nextInt(3)],
    };
  },
);

void main() async {
  print('=== Debug Response ID Capture ===\n');

  // Create the model directly to see what happens during streaming
  final provider = Providers.get('openai-responses');
  final model = provider.createChatModel(tools: [weatherTool]);
  
  print('Starting streaming to capture response ID...');
  
  final messages = [
    const ChatMessage(
      role: ChatMessageRole.user,
      parts: [TextPart('What is the weather in Boston?')],
    ),
  ];
  
  ChatResult<ChatMessage>? lastResult;
  await for (final result in model.sendStream(messages)) {
    lastResult = result;
    print('Result metadata: ${result.metadata}');
    
    // Look for tool calls
    for (final part in result.output.parts) {
      if (part is ToolPart && part.kind == ToolPartKind.call) {
        print('TOOL CALL FOUND:');
        print('  ID: ${part.id}');
        print('  Name: ${part.name}');
        print('  Args: ${part.arguments}');
      }
    }
    
    if (result.finishReason == FinishReason.stop) {
      print('Stream finished');
      print('Final metadata: ${result.metadata}');
      break;
    }
  }

  if (lastResult != null && lastResult!.metadata.containsKey('response_id')) {
    print('\nSUCCESS: Response ID captured: ${lastResult!.metadata['response_id']}');
  } else {
    print('\nFAILED: No response ID found in metadata');
    print('Available metadata keys: ${lastResult?.metadata.keys.toList()}');
  }

  exit(0);
}