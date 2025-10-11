import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';

void main() async {
  // Register Firebase AI providers with new naming
  Providers.providerMap['firebase-vertex'] = FirebaseAIProvider();
  Providers.providerMap['firebase-google'] = FirebaseAIProvider(
    backend: FirebaseAIBackend.googleAI,
  );
  
  const model = 'firebase-vertex:gemini-2.0-flash';
  await singleTurnChat(model);
  await singleTurnChatStream(model);
  await multiModalDemo(model);
  exit(0);
}

Future<void> singleTurnChat(String model) async {
  stdout.writeln('\n## Firebase AI Single Turn Chat');

  final agent = Agent(model);
  const prompt = 'What is Firebase AI and how does it work with Gemini models?';
  stdout.writeln('User: $prompt');
  
  try {
    final result = await agent.send(prompt);
    stdout.writeln('${agent.displayName}: ${result.output}');
    stdout.writeln('Usage: ${result.usage}');
  } catch (e) {
    stdout.writeln('Error: $e');
    stdout.writeln('Note: Firebase AI requires proper Firebase configuration');
  }
}

Future<void> singleTurnChatStream(String model) async {
  stdout.writeln('\n## Firebase AI Streaming Chat');

  final agent = Agent(model);
  const prompt = 'Count from 1 to 5, explaining each number';
  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');
  
  try {
    await for (final result in agent.sendStream(prompt)) {
      stdout.write(result.output);
    }
    stdout.writeln();
  } catch (e) {
    stdout.writeln('\nError: $e');
    stdout.writeln('Note: Firebase AI requires proper Firebase configuration');
  }
}

Future<void> multiModalDemo(String model) async {
  stdout.writeln('\n## Firebase AI Multi-modal Demo');

  // Demonstrate Firebase AI specific utilities
  stdout.writeln('Testing Firebase AI multi-modal validation...');
  
  // Test image validation with mock data
  const mimeType = 'image/jpeg';
  final mockImageBytes = <int>[0xFF, 0xD8, 0xFF]; // JPEG header
  
  stdout.writeln('Image validation result:');
  stdout.writeln('  - MIME type: $mimeType');
  stdout.writeln('  - Bytes length: ${mockImageBytes.length}');
  stdout.writeln('  - MIME type supported: ${FirebaseAIMultiModalUtils.isSupportedMediaType(mimeType)}');
  
  // Test Firebase AI streaming accumulator
  stdout.writeln('\nTesting Firebase AI streaming accumulator...');
  final accumulator = FirebaseAIStreamingAccumulator(modelName: 'gemini-2.0-flash');
  stdout.writeln('Accumulator initialized for model: ${accumulator.modelName}');
  
  // Test Firebase AI thinking utilities  
  stdout.writeln('\nFirebase AI utilities are ready for use!');
}