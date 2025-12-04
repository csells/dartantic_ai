// ignore_for_file: avoid_print

import 'dart:io' show Platform;

import 'package:dartantic_ai/dartantic_ai.dart';

import 'package:test/test.dart';

void main() {
  group('All Providers Text Duplication Tests', () {
    setUpAll(() {
      // Set up API keys for available providers
      final openaiKey = Platform.environment['OPENAI_API_KEY'];
      if (openaiKey != null && openaiKey.isNotEmpty) {
        Agent.environment['OPENAI_API_KEY'] = openaiKey;
      }

      final anthropicKey = Platform.environment['ANTHROPIC_API_KEY'];
      if (anthropicKey != null && anthropicKey.isNotEmpty) {
        Agent.environment['ANTHROPIC_API_KEY'] = anthropicKey;
      }

      final googleKey = Platform.environment['GOOGLE_API_KEY'];
      if (googleKey != null && googleKey.isNotEmpty) {
        Agent.environment['GOOGLE_API_KEY'] = googleKey;
      }
    });

    final providersToTest = [
      'openai',
      'openai-responses',
      if (Platform.environment['ANTHROPIC_API_KEY'] != null) 'anthropic',
      if (Platform.environment['GOOGLE_API_KEY'] != null) 'google',
    ];

    for (final provider in providersToTest) {
      group('Provider: $provider', () {
        test('should not duplicate text in streaming responses', () async {
          Agent agent;
          try {
            agent = Agent(provider);
          } on Exception catch (e) {
            // Skip if provider not available
            print('Skipping $provider: $e');
            return;
          }

          final streamedChunks = <String>[];
          final history = <ChatMessage>[];

          await for (final chunk in agent.sendStream(
            'Write exactly three words.',
          )) {
            // Collect text from streamed chunks
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

            history.addAll(chunk.messages);
          }

          final accumulatedText = streamedChunks.join();

          // Check for duplication in accumulated text
          expect(
            _hasTextDuplication(accumulatedText),
            isFalse,
            reason: '$provider streaming should not duplicate text',
          );

          // Check final message for duplication
          if (history.isNotEmpty) {
            final finalText = history.last.parts
                .whereType<TextPart>()
                .map((p) => p.text)
                .join();

            expect(
              _hasTextDuplication(finalText),
              isFalse,
              reason: '$provider final message should not duplicate text',
            );

            // Accumulated should match final
            expect(
              accumulatedText.trim(),
              equals(finalText.trim()),
              reason: '$provider: streamed text should match final message',
            );
          }
        });

        test('should not duplicate text in non-streaming responses', () async {
          Agent agent;
          try {
            agent = Agent(provider);
          } on Exception catch (e) {
            // Skip if provider not available
            print('Skipping $provider: $e');
            return;
          }

          final result = await agent.send('Write exactly four words.');

          final outputText = result.output;

          // Check for duplication
          expect(
            _hasTextDuplication(outputText),
            isFalse,
            reason: '$provider non-streaming should not duplicate text',
          );

          // Check message text
          if (result.messages.isNotEmpty) {
            final messageText = result.messages.last.parts
                .whereType<TextPart>()
                .map((p) => p.text)
                .join();

            expect(
              _hasTextDuplication(messageText),
              isFalse,
              reason: '$provider message should not duplicate text',
            );

            // Should match output
            expect(
              outputText.trim(),
              equals(messageText.trim()),
              reason: '$provider: output should match message text',
            );
          }
        });

        test('should handle multi-turn without duplication', () async {
          Agent agent;
          try {
            agent = Agent(provider);
          } on Exception catch (e) {
            // Skip if provider not available
            print('Skipping $provider: $e');
            return;
          }

          final history = <ChatMessage>[];

          // First turn
          final result1 = await agent.send(
            'Say "hello" once.',
            history: history,
          );
          history.addAll(result1.messages);

          expect(
            _hasTextDuplication(result1.output),
            isFalse,
            reason: '$provider first turn should not duplicate',
          );

          // Second turn
          final result2 = await agent.send(
            'Say "world" once.',
            history: history,
          );
          history.addAll(result2.messages);

          expect(
            _hasTextDuplication(result2.output),
            isFalse,
            reason: '$provider second turn should not duplicate',
          );

          // Check that each message is unique (no cross-message duplication)
          final allModelMessages = history
              .where((m) => m.role == ChatMessageRole.model)
              .map(
                (m) => m.parts.whereType<TextPart>().map((p) => p.text).join(),
              )
              .toList();

          // No message should be identical to another
          for (var i = 0; i < allModelMessages.length; i++) {
            for (var j = i + 1; j < allModelMessages.length; j++) {
              expect(
                allModelMessages[i],
                isNot(equals(allModelMessages[j])),
                reason: '$provider: messages should not be identical',
              );
            }
          }
        });
      });
    }
  });
}

/// Detects if text contains duplication
bool _hasTextDuplication(String text) {
  if (text.isEmpty || text.length < 10) return false;

  // Check for exact halves duplication
  if (text.length >= 20) {
    final halfLength = text.length ~/ 2;
    final firstHalf = text.substring(0, halfLength).trim();
    final secondHalf = text.substring(halfLength, halfLength * 2).trim();

    if (firstHalf == secondHalf && firstHalf.isNotEmpty) {
      print('Found exact duplication: "$firstHalf" == "$secondHalf"');
      return true;
    }
  }

  // Check for sentence/phrase repetition
  final sentences = text
      .split(RegExp(r'[.!?\n]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  if (sentences.length >= 2) {
    for (var i = 0; i < sentences.length; i++) {
      for (var j = i + 1; j < sentences.length; j++) {
        if (sentences[i] == sentences[j] && sentences[i].length > 10) {
          print('Found repeated sentence: "${sentences[i]}"');
          return true;
        }
      }
    }
  }

  // Check for repeated word sequences (5+ words)
  final words = text.split(RegExp(r'\s+'));
  if (words.length >= 10) {
    const minSequenceLength = 4;
    for (
      var seqLen = minSequenceLength;
      seqLen <= words.length ~/ 2;
      seqLen++
    ) {
      for (var i = 0; i <= words.length - seqLen * 2; i++) {
        final sequence = words.sublist(i, i + seqLen);
        // Look for this sequence later in the text
        for (var j = i + seqLen; j <= words.length - seqLen; j++) {
          final compareSequence = words.sublist(j, j + seqLen);
          if (sequence.join(' ') == compareSequence.join(' ')) {
            print('Found repeated sequence: "${sequence.join(' ')}"');
            return true;
          }
        }
      }
    }
  }

  return false;
}
