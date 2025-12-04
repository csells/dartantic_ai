import 'dart:io' show Platform;

import 'package:dartantic_ai/dartantic_ai.dart';

import 'package:test/test.dart';

void main() {
  group('OpenAI Responses Streaming Tests', () {
    setUpAll(() {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw StateError('OPENAI_API_KEY environment variable is required');
      }
      Agent.environment['OPENAI_API_KEY'] = apiKey;
    });

    test('should stream thinking deltas for reasoning models', () async {
      // Test with gpt-5 which supports thinking/reasoning
      final agent = Agent(
        'openai-responses:gpt-5',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          reasoningSummary: OpenAIReasoningSummary.detailed,
        ),
      );

      final thinkingBuffer = StringBuffer();
      final outputBuffer = StringBuffer();
      final history = <ChatMessage>[];

      await for (final chunk in agent.sendStream(
        'In one sentence: explain quicksort.',
      )) {
        if (chunk.thinking != null) {
          thinkingBuffer.write(chunk.thinking);
        }
        outputBuffer.write(chunk.output);
        history.addAll(chunk.messages);
      }

      expect(
        thinkingBuffer.toString(),
        isNotEmpty,
        reason: 'gpt-5 with detailed reasoning MUST produce thinking output',
      );

      expect(
        history.last.metadata.containsKey('thinking'),
        isFalse,
        reason: 'Thinking should NOT be in message metadata',
      );

      // Verify the actual response
      expect(
        outputBuffer.toString(),
        isNotEmpty,
        reason: 'Should have actual response output',
      );

      expect(
        outputBuffer.toString().toLowerCase(),
        contains('quicksort'),
        reason: 'Response should address the question',
      );
    });

    test('should not duplicate text in streaming responses', () async {
      final agent = Agent('openai-responses');
      final history = <ChatMessage>[];

      // Collect all streamed text
      final streamedChunks = <String>[];

      await for (final chunk in agent.sendStream(
        'Write a short haiku about programming.',
        history: history,
      )) {
        // Collect streamed text chunks
        if (chunk.output is ChatMessage) {
          final message = chunk.output as ChatMessage;
          for (final part in message.parts) {
            if (part is TextPart && part.text.isNotEmpty) {
              streamedChunks.add(part.text);
            }
          }
        } else if (chunk.output.isNotEmpty) {
          streamedChunks.add(chunk.output);
        }

        // Collect final messages
        history.addAll(chunk.messages);
      }

      // Get the final accumulated text
      final accumulatedText = streamedChunks.join();

      // Get the text from the final message in history
      final finalMessageText = history.isNotEmpty
          ? history.last.parts.whereType<TextPart>().map((p) => p.text).join()
          : '';

      // Check for text duplication
      expect(
        _hasTextDuplication(accumulatedText),
        isFalse,
        reason: 'Streamed text should not contain duplication',
      );

      expect(
        _hasTextDuplication(finalMessageText),
        isFalse,
        reason: 'Final message text should not contain duplication',
      );

      // The accumulated text should equal the final message text
      expect(
        accumulatedText.trim(),
        equals(finalMessageText.trim()),
        reason: 'Accumulated streamed text should match final message text',
      );

      // Verify metadata is present
      expect(
        history.last.metadata.containsKey('_responses_session'),
        isTrue,
        reason: 'Final message should have session metadata',
      );

      final sessionData =
          history.last.metadata['_responses_session'] as Map<String, Object?>;
      expect(
        sessionData.containsKey('response_id'),
        isTrue,
        reason: 'Session metadata should contain response_id',
      );
    });

    test('should not duplicate text in non-streaming responses', () async {
      final agent = Agent('openai-responses');
      final history = <ChatMessage>[];

      final result = await agent.send(
        'Write a short haiku about debugging.',
        history: history,
      );

      history.addAll(result.messages);

      // Get the output text
      final outputText = result.output;

      // Get the text from the message in history
      final messageText = history.last.parts
          .whereType<TextPart>()
          .map((p) => p.text)
          .join();

      // Check for text duplication
      expect(
        _hasTextDuplication(outputText),
        isFalse,
        reason: 'Non-streaming output should not contain duplication',
      );

      expect(
        _hasTextDuplication(messageText),
        isFalse,
        reason: 'Non-streaming message should not contain duplication',
      );

      // Output should match message text
      expect(
        outputText.trim(),
        equals(messageText.trim()),
        reason: 'Output should match message text in non-streaming',
      );

      // Verify metadata is present
      expect(
        history.last.metadata.containsKey('_responses_session'),
        isTrue,
        reason: 'Non-streaming message should have session metadata',
      );
    });

    test(
      'should handle multiple streaming turns without duplication',
      () async {
        final agent = Agent('openai-responses');
        final history = <ChatMessage>[];

        // First streaming turn
        await for (final chunk in agent.sendStream(
          'My name is TestBot.',
          history: history,
        )) {
          history.addAll(chunk.messages);
        }

        final firstMessageText = history.last.parts
            .whereType<TextPart>()
            .map((p) => p.text)
            .join();

        expect(
          _hasTextDuplication(firstMessageText),
          isFalse,
          reason: 'First turn should not have duplication',
        );

        // Second streaming turn
        await for (final chunk in agent.sendStream(
          'What is my name?',
          history: history,
        )) {
          history.addAll(chunk.messages);
        }

        final secondMessageText = history.last.parts
            .whereType<TextPart>()
            .map((p) => p.text)
            .join();

        expect(
          _hasTextDuplication(secondMessageText),
          isFalse,
          reason: 'Second turn should not have duplication',
        );

        // Verify both messages have session metadata
        expect(
          history[1].metadata.containsKey('_responses_session'),
          isTrue,
          reason: 'First model message should have session metadata',
        );

        expect(
          history[3].metadata.containsKey('_responses_session'),
          isTrue,
          reason: 'Second model message should have session metadata',
        );

        // The response IDs should be different
        final firstSession =
            history[1].metadata['_responses_session'] as Map<String, Object?>;
        final secondSession =
            history[3].metadata['_responses_session'] as Map<String, Object?>;

        expect(
          firstSession['response_id'],
          isNot(equals(secondSession['response_id'])),
          reason: 'Each turn should have a unique response ID',
        );
      },
    );

    test(
      'should provide thinking in result.thinking for non-streaming',
      () async {
        // Test with gpt-5 which supports thinking/reasoning
        final agent = Agent(
          'openai-responses:gpt-5',
          chatModelOptions: const OpenAIResponsesChatModelOptions(
            reasoningSummary: OpenAIReasoningSummary.detailed,
          ),
        );

        // Thinking is accumulated from streaming chunks by Agent.send()
        final result = await agent.send('Explain merge sort');

        // Thinking should be surfaced via ChatResult.thinking
        expect(
          result.thinking,
          isNotNull,
          reason:
              'Agent.send() should accumulate thinking from streaming chunks',
        );
        expect(
          result.thinking!.isNotEmpty,
          isTrue,
          reason: 'Thinking should contain content',
        );

        // Thinking is NOT in message metadata (only session info there)
        expect(
          result.messages.last.metadata.containsKey('thinking'),
          isFalse,
          reason: 'Message metadata should only contain session info',
        );

        // Verify we got a real response
        expect(
          result.output,
          isNotEmpty,
          reason: 'Should have actual response output',
        );
        expect(
          result.output.toLowerCase(),
          contains('merge'),
          reason: 'Response should address merge sort',
        );
      },
    );
  });
}

/// Detects if text contains duplication where the first half equals the
/// second half
bool _hasTextDuplication(String text) {
  if (text.isEmpty) return false;

  // Check for exact duplication (first half == second half)
  if (text.length >= 20) {
    // Only check if text is reasonably long
    final halfLength = text.length ~/ 2;
    final firstHalf = text.substring(0, halfLength);
    final secondHalf = text.substring(halfLength, halfLength * 2);

    if (firstHalf == secondHalf) {
      return true;
    }
  }

  // Check for repeated phrases (same phrase appears multiple times)
  // Split into words and check for repeated sequences
  final words = text.split(RegExp(r'\s+'));
  if (words.length >= 10) {
    // Check for repeated sequences of 5+ words
    const sequenceLength = 5;
    for (var i = 0; i <= words.length - sequenceLength * 2; i++) {
      final sequence = words.sublist(i, i + sequenceLength).join(' ');
      final restOfText = words.sublist(i + sequenceLength).join(' ');
      if (restOfText.contains(sequence)) {
        // Found repeated sequence
        return true;
      }
    }
  }

  return false;
}
