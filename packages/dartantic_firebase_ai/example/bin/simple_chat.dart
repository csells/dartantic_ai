import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';

/// Simple command-line example of Firebase AI provider usage.
///
/// This example shows basic text generation without the Flutter UI.
/// Run with: dart run example/bin/simple_chat.dart
void main() async {
  print('🔥 Firebase AI Provider Example');
  print('================================');

  try {
    // Initialize Firebase
    // Note: This requires proper Firebase configuration
    await Firebase.initializeApp();
    print('✅ Firebase initialized');

    // Create provider and model
    final provider = FirebaseAIProvider();
    final chatModel = provider.createChatModel(
      name: 'gemini-2.0-flash',
      temperature: 0.7,
    );
    print('✅ Firebase AI model created');

    // Chat loop
    final messages = <ChatMessage>[];

    while (true) {
      stdout.write('\n💬 You: ');
      final input = stdin.readLineSync();

      if (input == null || input.toLowerCase() == 'quit') {
        break;
      }

      if (input.trim().isEmpty) {
        continue;
      }

      messages.add(ChatMessage.user(input));

      stdout.write('🤖 AI: ');

      try {
        ChatResult<ChatMessage>? finalResult;
        await for (final chunk in chatModel.sendStream(messages)) {
          // Print each chunk as it arrives (streaming)
          for (final message in chunk.messages) {
            if (message.role == ChatMessageRole.model) {
              stdout.write(message.text);
            }
          }
          finalResult = chunk;
        }

        print(''); // New line after response

        // Add final message to history
        if (finalResult != null) {
          messages.addAll(finalResult.messages);
        }
      } catch (e) {
        print('❌ Error: $e');
      }
    }

    print('\n👋 Goodbye!');
    chatModel.dispose();
  } catch (e) {
    print('❌ Failed to initialize: $e');
    print('');
    print('💡 Make sure you have:');
    print('   1. Configured Firebase with `flutterfire configure`');
    print('   2. Enabled Firebase AI Logic in your Firebase console');
    print('   3. Set up proper authentication/App Check');
    exit(1);
  }
}
