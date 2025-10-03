import 'dart:io' show Platform;

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAI Responses Session Persistence Tests', () {
    // Track messages sent to API
    final sentMessageCounts = <int>[];
    final previousResponseIds = <String?>[];

    setUpAll(() {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw StateError('OPENAI_API_KEY environment variable is required');
      }
      Agent.environment['OPENAI_API_KEY'] = apiKey;

      // Enable logging to capture session persistence behavior
      Logger.root.level = Level.INFO;
      Logger.root.onRecord.listen((record) {
        if (record.loggerName.contains('openai_responses')) {
          // Extract information about messages being sent
          final message = record.message;
          if (message.contains('Sending only')) {
            // Extract the number of messages being sent
            final match = RegExp(
              r'Sending only (\d+) NEW messages',
            ).firstMatch(message);
            if (match != null) {
              sentMessageCounts.add(int.parse(match.group(1)!));
            }
          } else if (message.contains('✗ No previous session found')) {
            // No session, all messages sent
            final match = RegExp(
              r'sending all (\d+) messages',
            ).firstMatch(message);
            if (match != null) {
              sentMessageCounts.add(
                int.parse(match.group(1)!) + 1,
              ); // +1 for current message
            } else {
              sentMessageCounts.add(1); // Just the current message
            }
            previousResponseIds.add(null);
          } else if (message.contains('Previous response ID:')) {
            // Extract the previous response ID being used
            final match = RegExp(
              r'Previous response ID: (\S+)',
            ).firstMatch(message);
            if (match != null) {
              previousResponseIds.add(match.group(1));
            }
          }
        }
      });
    });

    setUp(() {
      sentMessageCounts.clear();
      previousResponseIds.clear();
    });

    test(
      'should only send new messages when returning to OpenAI Responses',
      () async {
        final history = <ChatMessage>[];

        // Step 1: First OpenAI Responses call (no previous session)
        final agent1 = Agent('openai-responses');
        final result1 = await agent1.send(
          'My name is Alice and I work as a software engineer.',
          history: history,
        );
        history.addAll(result1.messages);

        expect(
          sentMessageCounts.isNotEmpty,
          isTrue,
          reason: 'Should have tracked message count for first call',
        );
        expect(
          sentMessageCounts.first,
          equals(1),
          reason:
              'First call should send only the current message (no history)',
        );

        // Verify session metadata was stored
        expect(
          history.last.metadata.containsKey('_responses_session'),
          isTrue,
          reason: 'First response should store session metadata',
        );

        final firstSessionId =
            (history.last.metadata['_responses_session']
                    as Map<String, Object?>)['response_id']!
                as String;

        // Step 2: Use a different provider (OpenAI standard)
        final agent2 = Agent('openai');
        final result2 = await agent2.send(
          'What did I just tell you?',
          history: history,
        );
        history.addAll(result2.messages);

        // Standard OpenAI shouldn't affect Responses sessions
        expect(
          history.last.metadata.containsKey('_responses_session'),
          isFalse,
          reason: 'Standard OpenAI should not have Responses session metadata',
        );

        // Step 3: Use another different provider (if available)
        // We'll use OpenAI again but it could be any non-Responses provider
        final agent3 = Agent('openai');
        final result3 = await agent3.send(
          'Can you remember my profession?',
          history: history,
        );
        history.addAll(result3.messages);

        // Step 4: Return to OpenAI Responses (should find session from step 1)
        sentMessageCounts.clear(); // Clear to track only this call
        previousResponseIds.clear();

        final agent4 = Agent('openai-responses');
        final result4 = await agent4.send(
          'What is my name and profession?',
          history: history,
        );
        history.addAll(result4.messages);

        expect(
          sentMessageCounts.isNotEmpty,
          isTrue,
          reason: 'Should have tracked message count for second Responses call',
        );

        // Should send only messages after the first Responses call
        // History has: user(1), model(1), user(2), model(2), user(3),
        // model(3), user(4)
        // Should send from index 2 onwards = 5 messages
        expect(
          sentMessageCounts.first,
          equals(5),
          reason:
              'Second Responses call should only send messages '
              'after first session',
        );

        expect(
          previousResponseIds.isNotEmpty,
          isTrue,
          reason: 'Should have tracked previous response ID',
        );

        expect(
          previousResponseIds.first,
          equals(firstSessionId),
          reason: 'Should use the response ID from first Responses call',
        );

        // Verify new session metadata was stored
        expect(
          history.last.metadata.containsKey('_responses_session'),
          isTrue,
          reason: 'Second Responses call should store session metadata',
        );

        final secondSessionId =
            (history.last.metadata['_responses_session']
                    as Map<String, Object?>)['response_id']!
                as String;

        expect(
          secondSessionId,
          isNot(equals(firstSessionId)),
          reason: 'Second call should have a different response ID',
        );

        // Step 5: Third OpenAI Responses call (should find session from step 4)
        sentMessageCounts.clear();
        previousResponseIds.clear();

        final agent5 = Agent('openai-responses');
        final result5 = await agent5.send(
          'Give me a summary of what you know about me.',
          history: history,
        );
        history.addAll(result5.messages);

        expect(
          sentMessageCounts.isNotEmpty,
          isTrue,
          reason: 'Should have tracked message count for third Responses call',
        );

        // Should send only messages after the second Responses call
        // Only the new user message since last Responses call
        expect(
          sentMessageCounts.first,
          equals(1),
          reason: 'Third Responses call should only send new message',
        );

        expect(
          previousResponseIds.first,
          equals(secondSessionId),
          reason: 'Should use the response ID from second Responses call',
        );
      },
    );

    test('should handle streaming with session persistence', () async {
      final history = <ChatMessage>[];

      // First streaming call with OpenAI Responses
      final agent1 = Agent('openai-responses');
      await for (final chunk in agent1.sendStream(
        'My favorite color is blue.',
        history: history,
      )) {
        history.addAll(chunk.messages);
      }

      expect(
        history.last.metadata.containsKey('_responses_session'),
        isTrue,
        reason: 'Streaming should preserve session metadata',
      );

      final firstSessionId =
          (history.last.metadata['_responses_session']
                  as Map<String, Object?>)['response_id']!
              as String;

      // Interleave with non-Responses provider
      final agent2 = Agent('openai');
      final result2 = await agent2.send(
        'What else would you like to know?',
        history: history,
      );
      history.addAll(result2.messages);

      // Second streaming call with OpenAI Responses
      sentMessageCounts.clear();
      previousResponseIds.clear();

      final agent3 = Agent('openai-responses');
      await for (final chunk in agent3.sendStream(
        'What is my favorite color?',
        history: history,
      )) {
        history.addAll(chunk.messages);
      }

      expect(
        previousResponseIds.isNotEmpty &&
            previousResponseIds.first == firstSessionId,
        isTrue,
        reason: 'Second streaming call should use session from first call',
      );

      expect(
        history.last.metadata.containsKey('_responses_session'),
        isTrue,
        reason: 'Second streaming call should preserve session metadata',
      );
    });

    test(
      'should find most recent Responses session when multiple exist',
      () async {
        final history = <ChatMessage>[];

        // First OpenAI Responses call
        final agent1 = Agent('openai-responses');
        final result1 = await agent1.send('First message.', history: history);
        history.addAll(result1.messages);

        final firstSessionId =
            (history.last.metadata['_responses_session']
                    as Map<String, Object?>)['response_id']!
                as String;

        // Interleave with other provider
        final agent2 = Agent('openai');
        final result2 = await agent2.send('Other provider.', history: history);
        history.addAll(result2.messages);

        // Second OpenAI Responses call
        final agent3 = Agent('openai-responses');
        final result3 = await agent3.send('Second message.', history: history);
        history.addAll(result3.messages);

        final secondSessionId =
            (history.last.metadata['_responses_session']
                    as Map<String, Object?>)['response_id']!
                as String;

        // More interleaving
        final agent4 = Agent('openai');
        final result4 = await agent4.send('Another message.', history: history);
        history.addAll(result4.messages);

        // Third OpenAI Responses call should find SECOND session, not first
        sentMessageCounts.clear();
        previousResponseIds.clear();

        final agent5 = Agent('openai-responses');
        final result5 = await agent5.send('Third message.', history: history);
        history.addAll(result5.messages);

        expect(
          previousResponseIds.first,
          equals(secondSessionId),
          reason: 'Should use most recent Responses session, not the first one',
        );

        expect(
          previousResponseIds.first,
          isNot(equals(firstSessionId)),
          reason: 'Should NOT use the older first session',
        );
      },
    );
  });

  group('OpenAI Responses Server-Side Tools Execution', () {
    test('code interpreter executes Python code', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.codeInterpreter},
        ),
      );

      final result = await agent.send(
        'Calculate 15 * 23 using Python code and show me the result.',
      );

      // Should have executed code and returned result
      expect(result.output, contains('345'));
      expect(result.messages, isNotEmpty);
    });

    test('code interpreter container reuse across turns', () async {
      final history = <ChatMessage>[];
      String? firstContainerId;
      String? secondContainerId;

      // First turn: Create variable in container
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.codeInterpreter},
        ),
      );

      await for (final chunk in agent.sendStream(
        'Calculate the first 5 Fibonacci numbers and store in variable "fib".',
      )) {
        history.addAll(chunk.messages);

        // Extract container_id from streaming metadata
        final ciEvents = chunk.metadata['code_interpreter'] as List?;
        if (ciEvents != null) {
          for (final event in ciEvents) {
            final item = event['item'];
            if (item is Map && item['container_id'] != null) {
              firstContainerId = item['container_id'] as String;
            }
          }
        }
      }

      expect(firstContainerId, isNotNull, reason: 'Should have container ID');

      // Second turn: Reuse variable from first turn
      await for (final chunk in agent.sendStream(
        'What is the sum of the fib variable?',
        history: history,
      )) {
        history.addAll(chunk.messages);

        // Extract container_id from streaming metadata
        final ciEvents = chunk.metadata['code_interpreter'] as List?;
        if (ciEvents != null) {
          for (final event in ciEvents) {
            final item = event['item'];
            if (item is Map && item['container_id'] != null) {
              secondContainerId = item['container_id'] as String;
            }
          }
        }
      }

      // Container should be reused
      expect(
        secondContainerId,
        equals(firstContainerId),
        reason: 'Container should be reused across turns',
      );
    });

    test('web search returns search results', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.webSearch},
        ),
      );

      final result = await agent.send(
        'What is the current population of Tokyo?',
      );

      // Should have performed web search and included results
      expect(result.output, isNotEmpty);
      expect(
        result.output.toLowerCase(),
        anyOf(
          contains('million'),
          contains('tokyo'),
          contains('population'),
        ),
      );
    });

    test('image generation produces DataPart with image', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.imageGeneration},
          imageGenerationConfig: ImageGenerationConfig(
            size: ImageGenerationSize.square256,
            quality: ImageGenerationQuality.low,
          ),
        ),
      );

      final history = <ChatMessage>[];
      await for (final chunk in agent.sendStream(
        'Generate a simple blue square image.',
      )) {
        history.addAll(chunk.messages);
      }

      // Should have image in final message
      final imageParts = history.last.parts.whereType<DataPart>();
      expect(imageParts, isNotEmpty, reason: 'Should have image DataPart');

      final imagePart = imageParts.first;
      expect(
        imagePart.mimeType,
        startsWith('image/'),
        reason: 'Should be an image MIME type',
      );
      expect(
        imagePart.bytes.length,
        greaterThan(100),
        reason: 'Image should have content',
      );
    });
  });
}
