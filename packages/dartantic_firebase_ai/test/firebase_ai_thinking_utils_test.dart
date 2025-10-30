/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'dart:typed_data';
import 'package:dartantic_firebase_ai/src/firebase_ai_thinking_utils.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

void main() {
  group('FirebaseAIThinkingOptions', () {
    test('creates default options', () {
      const options = FirebaseAIThinkingOptions();
      
      expect(options.enabled, isFalse);
      expect(options.includeReasoningSteps, isTrue);
      expect(options.includeSafetyAnalysis, isTrue);
      expect(options.verboseCitationMetadata, isFalse);
    });

    test('creates custom options', () {
      const options = FirebaseAIThinkingOptions(
        enabled: true,
        includeReasoningSteps: false,
        includeSafetyAnalysis: false,
        verboseCitationMetadata: true,
      );
      
      expect(options.enabled, isTrue);
      expect(options.includeReasoningSteps, isFalse);
      expect(options.includeSafetyAnalysis, isFalse);
      expect(options.verboseCitationMetadata, isTrue);
    });
  });

  group('FirebaseAIThinkingUtils', () {
    group('extractThinking', () {
      test('returns null when thinking is disabled', () {
        final result = _createTestResult();
        const options = FirebaseAIThinkingOptions(enabled: false);
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        expect(thinking, isNull);
      });

      test('extracts safety analysis when enabled', () {
        final result = _createTestResult(metadata: {
          'safety_ratings': [
            {'category': 'HARM_CATEGORY_HARASSMENT', 'probability': 'LOW'},
            {'category': 'HARM_CATEGORY_HATE_SPEECH', 'probability': 'NEGLIGIBLE'},
          ],
        });
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeSafetyAnalysis: true,
          includeReasoningSteps: false,
          verboseCitationMetadata: false,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        expect(thinking, isNotNull);
        expect(thinking!, contains('[SAFETY ANALYSIS]'));
        expect(thinking, contains('HARM_CATEGORY_HARASSMENT: LOW'));
        expect(thinking, contains('HARM_CATEGORY_HATE_SPEECH: NEGLIGIBLE'));
      });

      test('skips safety analysis when disabled', () {
        final result = _createTestResult(metadata: {
          'safety_ratings': [
            {'category': 'HARM_CATEGORY_HARASSMENT', 'probability': 'LOW'},
          ],
        });
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeSafetyAnalysis: false,
          includeReasoningSteps: false,
          verboseCitationMetadata: false,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        expect(thinking, isNull); // No content extracted
      });

      test('extracts content filtering reasoning', () {
        final result = _createTestResult(metadata: {
          'block_reason': 'SAFETY',
          'block_reason_message': 'Content contains potentially harmful information',
        });
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeReasoningSteps: true,
          includeSafetyAnalysis: false,
          verboseCitationMetadata: false,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        expect(thinking, isNotNull);
        expect(thinking!, contains('[CONTENT FILTERING REASONING]'));
        expect(thinking, contains('Block Reason: SAFETY'));
        expect(thinking, contains('Reasoning: Content contains potentially harmful information'));
      });

      test('extracts completion reasoning', () {
        final result = _createTestResult(metadata: {
          'finish_message': 'Response completed successfully with all requirements met',
        });
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeReasoningSteps: true,
          includeSafetyAnalysis: false,
          verboseCitationMetadata: false,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        expect(thinking, isNotNull);
        expect(thinking!, contains('[COMPLETION REASONING]'));
        expect(thinking, contains('Response completed successfully with all requirements met'));
      });

      test('extracts citation metadata when verbose mode enabled', () {
        final result = _createTestResult(metadata: {
          'citation_metadata': 'Sources: Wikipedia, Stack Overflow, Academic Papers',
        });
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          verboseCitationMetadata: true,
          includeReasoningSteps: false,
          includeSafetyAnalysis: false,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        expect(thinking, isNotNull);
        expect(thinking!, contains('[CITATION ANALYSIS]'));
        expect(thinking, contains('Sources: Wikipedia, Stack Overflow, Academic Papers'));
      });

      test('skips citation metadata when verbose mode disabled', () {
        final result = _createTestResult(metadata: {
          'citation_metadata': 'Sources: Wikipedia, Stack Overflow, Academic Papers',
        });
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          verboseCitationMetadata: false,
          includeReasoningSteps: false,
          includeSafetyAnalysis: false,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        expect(thinking, isNull); // No content extracted
      });

      test('extracts reasoning patterns from model output', () {
        final result = _createTestResult(
          message: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              TextPart('Let me think about this problem. First, I need to analyze the data.'),
            ],
          ),
        );
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeReasoningSteps: false,
          includeSafetyAnalysis: false,
          verboseCitationMetadata: false,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        expect(thinking, isNotNull);
        expect(thinking!, contains('[DETECTED REASONING PATTERNS]'));
        expect(thinking, contains('Let me think:'));
        expect(thinking, contains('First, I need to:'));
      });

      test('combines multiple thinking components', () {
        final result = _createTestResult(
          message: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              TextPart('Let me analyze this step by step. The reason is clear.'),
            ],
          ),
          metadata: {
            'safety_ratings': [
              {'category': 'HARM_CATEGORY_HARASSMENT', 'probability': 'LOW'},
            ],
            'block_reason': 'SAFETY',
            'citation_metadata': 'Source: Academic research',
            'finish_message': 'Analysis complete',
          },
        );
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeReasoningSteps: true,
          includeSafetyAnalysis: true,
          verboseCitationMetadata: true,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        expect(thinking, isNotNull);
        expect(thinking!, contains('[SAFETY ANALYSIS]'));
        expect(thinking, contains('[CONTENT FILTERING REASONING]'));
        expect(thinking, contains('[COMPLETION REASONING]'));
        expect(thinking, contains('[CITATION ANALYSIS]'));
        expect(thinking, contains('[DETECTED REASONING PATTERNS]'));
      });

      test('handles malformed safety ratings gracefully', () {
        final result = _createTestResult(metadata: {
          'safety_ratings': [
            'invalid_rating', // Not a map
            {'category': 'VALID_CATEGORY'}, // Missing probability
            {'probability': 'LOW'}, // Missing category
          ],
        });
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeSafetyAnalysis: true,
          includeReasoningSteps: false,
          verboseCitationMetadata: false,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        expect(thinking, isNotNull);
        expect(thinking!, contains('[SAFETY ANALYSIS]'));
        // Should not contain invalid entries
        expect(thinking, isNot(contains('invalid_rating')));
        expect(thinking, isNot(contains('VALID_CATEGORY')));
        expect(thinking, isNot(contains('LOW')));
      });

      test('handles empty metadata gracefully', () {
        final result = _createTestResult(metadata: {});
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeReasoningSteps: true,
          includeSafetyAnalysis: true,
          verboseCitationMetadata: true,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        expect(thinking, isNull); // No content to extract
      });

      test('handles null/empty strings in metadata', () {
        final result = _createTestResult(metadata: {
          'block_reason': null,
          'block_reason_message': '',
          'finish_message': null,
          'citation_metadata': '',
        });
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeReasoningSteps: true,
          includeSafetyAnalysis: true,
          verboseCitationMetadata: true,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(
          result,
          options: options,
        );
        
        // Empty string in block_reason_message still generates content
        expect(thinking, isNotNull);
      });

      test('throws exception on invalid metadata types', () {
        // Create a result that will cause an exception during processing
        final result = ChatResult<ChatMessage>(
          id: 'test',
          output: const ChatMessage(role: ChatMessageRole.model, parts: []),
          messages: const [],
          finishReason: FinishReason.stop,
          metadata: {
            'safety_ratings': 'invalid_type', // Will cause cast exception
          },
          usage: null,
        );
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeSafetyAnalysis: true,
        );
        
        expect(
          () => FirebaseAIThinkingUtils.extractThinking(result, options: options),
          throwsA(isA<TypeError>()),
        );
      });
    });

    group('reasoning pattern extraction', () {
      test('detects "Let me think" patterns', () {
        final result = _createTestResult(
          message: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              TextPart('Let me think about this problem carefully.'),
            ],
          ),
        );
        
        const options = FirebaseAIThinkingOptions(enabled: true);
        final thinking = FirebaseAIThinkingUtils.extractThinking(result, options: options);
        
        expect(thinking, contains('Let me think:'));
      });

      test('detects "First, I need to" patterns', () {
        final result = _createTestResult(
          message: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              TextPart('First, I need to understand the requirements.'),
            ],
          ),
        );
        
        const options = FirebaseAIThinkingOptions(enabled: true);
        final thinking = FirebaseAIThinkingUtils.extractThinking(result, options: options);
        
        expect(thinking, contains('First, I need to:'));
      });

      test('detects "The reason is" patterns', () {
        final result = _createTestResult(
          message: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              TextPart('The reason is that we need better error handling.'),
            ],
          ),
        );
        
        const options = FirebaseAIThinkingOptions(enabled: true);
        final thinking = FirebaseAIThinkingUtils.extractThinking(result, options: options);
        
        expect(thinking, contains('The reason is:'));
      });

      test('detects multiple reasoning patterns', () {
        final result = _createTestResult(
          message: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              TextPart('Let me analyze this step by step. The reason is complexity.'),
            ],
          ),
        );
        
        const options = FirebaseAIThinkingOptions(enabled: true);
        final thinking = FirebaseAIThinkingUtils.extractThinking(result, options: options);
        
        expect(thinking, contains('Let me analyze:'));
        expect(thinking, contains('Step by step:'));
        expect(thinking, contains('The reason is:'));
      });

      test('handles case-insensitive pattern matching', () {
        final result = _createTestResult(
          message: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              TextPart('LET ME THINK about this. THE REASON IS clear.'),
            ],
          ),
        );
        
        const options = FirebaseAIThinkingOptions(enabled: true);
        final thinking = FirebaseAIThinkingUtils.extractThinking(result, options: options);
        
        expect(thinking, contains('Let me think:'));
        expect(thinking, contains('The reason is:'));
      });

      test('extracts reasoning from multiple text parts', () {
        final result = _createTestResult(
          message: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              TextPart('Let me think about part one.'),
              TextPart('This is because of part two.'),
            ],
          ),
        );
        
        const options = FirebaseAIThinkingOptions(enabled: true);
        final thinking = FirebaseAIThinkingUtils.extractThinking(result, options: options);
        
        expect(thinking, contains('Let me think:'));
        expect(thinking, contains('This is because:'));
      });

      test('ignores non-text parts', () {
        final result = _createTestResult(
          message: ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              const TextPart('Let me analyze this.'),
              DataPart(Uint8List.fromList([1, 2, 3]), mimeType: 'image/png'),
            ],
          ),
        );
        
        const options = FirebaseAIThinkingOptions(enabled: true);
        final thinking = FirebaseAIThinkingUtils.extractThinking(result, options: options);
        
        expect(thinking, contains('Let me analyze:'));
        // Should not crash on DataPart
      });
    });

    group('addThinkingMetadata', () {
      test('returns original result when thinking disabled', () {
        final originalResult = _createTestResult();
        const options = FirebaseAIThinkingOptions(enabled: false);
        
        final result = FirebaseAIThinkingUtils.addThinkingMetadata(
          originalResult,
          options,
        );
        
        expect(result, same(originalResult));
      });

      test('returns original result when no thinking content extracted', () {
        final originalResult = _createTestResult(metadata: {});
        const options = FirebaseAIThinkingOptions(enabled: true);
        
        final result = FirebaseAIThinkingUtils.addThinkingMetadata(
          originalResult,
          options,
        );
        
        expect(result, same(originalResult));
      });

      test('adds thinking metadata when content is extracted', () {
        final originalResult = _createTestResult(metadata: {
          'safety_ratings': [
            {'category': 'HARM_CATEGORY_HARASSMENT', 'probability': 'LOW'},
          ],
          'existing_key': 'existing_value',
        });
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeSafetyAnalysis: true,
        );
        
        final result = FirebaseAIThinkingUtils.addThinkingMetadata(
          originalResult,
          options,
        );
        
        expect(result, isNot(same(originalResult)));
        expect(result.id, equals(originalResult.id));
        expect(result.output, equals(originalResult.output));
        expect(result.messages, equals(originalResult.messages));
        expect(result.finishReason, equals(originalResult.finishReason));
        expect(result.usage, equals(originalResult.usage));
        
        // Should preserve existing metadata
        expect(result.metadata['existing_key'], equals('existing_value'));
        
        // Should add thinking metadata
        expect(result.metadata['thinking'], isNotNull);
        expect(result.metadata['thinking'], contains('[SAFETY ANALYSIS]'));
      });

      test('preserves all metadata fields when adding thinking', () {
        final originalResult = _createTestResult(metadata: {
          'model_version': '1.5',
          'request_id': 'req-123',
          'safety_ratings': [
            {'category': 'HARM_CATEGORY_HARASSMENT', 'probability': 'LOW'},
          ],
        });
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeSafetyAnalysis: true,
        );
        
        final result = FirebaseAIThinkingUtils.addThinkingMetadata(
          originalResult,
          options,
        );
        
        expect(result.metadata['model_version'], equals('1.5'));
        expect(result.metadata['request_id'], equals('req-123'));
        expect(result.metadata['safety_ratings'], isNotNull);
        expect(result.metadata['thinking'], isNotNull);
      });
    });

    group('edge cases and error handling', () {
      test('handles result with empty parts list', () {
        final result = _createTestResult(
          message: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [],
          ),
        );
        
        const options = FirebaseAIThinkingOptions(enabled: true);
        final thinking = FirebaseAIThinkingUtils.extractThinking(result, options: options);
        
        expect(thinking, isNull); // No content to extract
      });

      test('handles extremely long reasoning patterns', () {
        final longText = 'Let me think about this: ${'very ' * 1000}complex problem.';
        final result = _createTestResult(
          message: ChatMessage(
            role: ChatMessageRole.model,
            parts: [TextPart(longText)],
          ),
        );
        
        const options = FirebaseAIThinkingOptions(enabled: true);
        final thinking = FirebaseAIThinkingUtils.extractThinking(result, options: options);
        
        expect(thinking, isNotNull);
        expect(thinking!, contains('Let me think:'));
      });

      test('handles special characters in metadata', () {
        final result = _createTestResult(metadata: {
          'finish_message': 'Complete with émojis 🎉 and special chars: <>&"\'',
        });
        
        const options = FirebaseAIThinkingOptions(
          enabled: true,
          includeReasoningSteps: true,
        );
        
        final thinking = FirebaseAIThinkingUtils.extractThinking(result, options: options);
        
        expect(thinking, isNotNull);
        expect(thinking!, contains('Complete with émojis 🎉'));
      });
    });
  });
}

// Test helper functions
ChatResult<ChatMessage> _createTestResult({
  ChatMessage? message,
  Map<String, dynamic>? metadata,
}) {
  return ChatResult<ChatMessage>(
    id: 'test-result',
    output: message ?? const ChatMessage(
      role: ChatMessageRole.model,
      parts: [TextPart('Test response')],
    ),
    messages: const [],
    finishReason: FinishReason.stop,
    metadata: metadata ?? {},
    usage: null,
  );
}