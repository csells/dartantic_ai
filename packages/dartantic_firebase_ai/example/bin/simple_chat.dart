import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:dartantic_firebase_ai/dartantic_firebase_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

/// Simple command-line example of Firebase AI provider usage.
///
/// This example shows basic text generation without the Flutter UI.
/// Run with: dart run example/bin/simple_chat.dart
void main() async {
  final Logger logger = Logger('dartantic.examples.firebase_ai');
  
  logger.info('🔥 Firebase AI Provider Example');
  logger.info('================================');

  try {
    // Initialize Firebase
    // Note: This requires proper Firebase configuration
    await Firebase.initializeApp();
    logger.info('✅ Firebase initialized');

    // Create provider and model
    final provider = FirebaseAIProvider();
    final chatModel = provider.createChatModel(
      name: 'gemini-2.0-flash',
      temperature: 0.7,
    );
    logger.info('✅ Firebase AI model created');

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

        logger.info(''); // New line after response

        // Add final message to history
        if (finalResult != null) {
          messages.addAll(finalResult.messages);
        }
      } catch (e) {
        logger.severe('❌ Error: $e');
      }
    }

    logger.info('\n👋 Goodbye!');
    chatModel.dispose();
  } catch (e) {
    logger.severe('❌ Failed to initialize: $e');
    logger.info('');
    logger.info('💡 Make sure you have:');
    logger.info('   1. Configured Firebase with `flutterfire configure`');
    logger.info('   2. Enabled Firebase AI Logic in your Firebase console');
    logger.info('   3. Set up proper authentication/App Check');
    exit(1);
  }
}
