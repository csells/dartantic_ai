/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'dart:typed_data';

import 'package:dartantic_firebase_ai/src/firebase_ai_streaming_accumulator.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

void main() {
  group('FirebaseAIStreamingAccumulator', () {
    late FirebaseAIStreamingAccumulator accumulator;

    setUp(() {
      accumulator = FirebaseAIStreamingAccumulator(
        modelName: 'gemini-1.5-pro',
      );
    });

    group('Constructor and Properties', () {
      test('creates accumulator with model name', () {
        expect(accumulator.modelName, equals('gemini-1.5-pro'));
        expect(accumulator.accumulatedTextLength, equals(0));
        expect(accumulator.chunkCount, equals(0));
        expect(accumulator.hasThinking, isFalse);
        expect(accumulator.hasSafetyRatings, isFalse);
      });
    });

    group('Text Accumulation', () {
      test('accumulates single text part correctly', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [TextPart('Hello world')],
          ),
          messages: const [],
          finishReason: FinishReason.unspecified,
          metadata: const {},
          usage: null,
        );

        accumulator.add(result);

        expect(accumulator.accumulatedTextLength, equals(11));
        expect(accumulator.chunkCount, equals(1));
      });

      test('accumulates multiple text chunks correctly', () {
        final chunks = [
          ChatResult<ChatMessage>(
            id: 'test-1',
            output: const ChatMessage(
              role: ChatMessageRole.model,
              parts: [TextPart('Hello ')],
            ),
            messages: const [],
            finishReason: FinishReason.unspecified,
            metadata: const {},
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-2',
            output: const ChatMessage(
              role: ChatMessageRole.model,
              parts: [TextPart('beautiful ')],
            ),
            messages: const [],
            finishReason: FinishReason.unspecified,
            metadata: const {},
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-3',
            output: const ChatMessage(
              role: ChatMessageRole.model,
              parts: [TextPart('world!')],
            ),
            messages: const [],
            finishReason: FinishReason.stop,
            metadata: const {},
            usage: const LanguageModelUsage(
              promptTokens: 10,
              responseTokens: 15,
              totalTokens: 25,
            ),
          ),
        ];

        for (final chunk in chunks) {
          accumulator.add(chunk);
        }

        expect(accumulator.accumulatedTextLength, equals(22));
        expect(accumulator.chunkCount, equals(3));

        final finalResult = accumulator.buildFinal();
        expect(finalResult.output.text, equals('Hello beautiful world!'));
        expect(finalResult.finishReason, equals(FinishReason.stop));
        expect(finalResult.usage?.totalTokens, equals(25));
      });

      test('handles empty text parts gracefully', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [TextPart('')],
          ),
          messages: const [],
          finishReason: FinishReason.unspecified,
          metadata: const {},
          usage: null,
        );

        accumulator.add(result);

        expect(accumulator.accumulatedTextLength, equals(0));
        expect(accumulator.chunkCount, equals(1));
      });

      test('ignores non-text parts', () {
        // Create a data part to test filtering
        final dataPart = DataPart(
          Uint8List.fromList([1, 2, 3, 4]),
          mimeType: 'application/octet-stream',
        );

        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              const TextPart('Hello'),
              dataPart,
              const TextPart(' world'),
            ],
          ),
          messages: const [],
          finishReason: FinishReason.unspecified,
          metadata: const {},
          usage: null,
        );

        accumulator.add(result);

        // Should only accumulate text parts
        expect(accumulator.accumulatedTextLength, equals(11));
        
        final finalResult = accumulator.buildFinal();
        expect(finalResult.output.text, equals('Hello world'));
      });
    });

    group('Message Accumulation', () {
      test('accumulates messages correctly', () {
        final chunks = [
          ChatResult<ChatMessage>(
            id: 'test-1',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [
              ChatMessage(
                role: ChatMessageRole.user,
                parts: [TextPart('What is AI?')],
              ),
            ],
            finishReason: FinishReason.unspecified,
            metadata: const {},
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-2',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [
              ChatMessage(
                role: ChatMessageRole.model,
                parts: [TextPart('AI stands for Artificial Intelligence')],
              ),
            ],
            finishReason: FinishReason.stop,
            metadata: const {},
            usage: null,
          ),
        ];

        for (final chunk in chunks) {
          accumulator.add(chunk);
        }

        final finalResult = accumulator.buildFinal();
        expect(finalResult.messages, hasLength(2));
        expect(finalResult.messages[0].role, equals(ChatMessageRole.user));
        expect(finalResult.messages[1].role, equals(ChatMessageRole.model));
        expect(finalResult.messages[0].text, equals('What is AI?'));
        expect(finalResult.messages[1].text, equals('AI stands for Artificial Intelligence'));
      });

      test('handles empty messages list', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [TextPart('Hello')],
          ),
          messages: const [],
          finishReason: FinishReason.stop,
          metadata: const {},
          usage: null,
        );

        accumulator.add(result);

        final finalResult = accumulator.buildFinal();
        // Should use the output as the final message when no messages are provided
        expect(finalResult.messages, hasLength(1));
        expect(finalResult.messages[0].text, equals('Hello'));
        expect(finalResult.messages[0].role, equals(ChatMessageRole.model));
      });
    });

    group('Thinking Content Accumulation', () {
      test('accumulates thinking content correctly', () {
        final chunks = [
          ChatResult<ChatMessage>(
            id: 'test-1',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.unspecified,
            metadata: const {'thinking': 'Let me think about this...'},
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-2',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.unspecified,
            metadata: const {'thinking': ' I need to consider...'},
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-3',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.stop,
            metadata: const {'thinking': ' the implications.'},
            usage: null,
          ),
        ];

        for (final chunk in chunks) {
          accumulator.add(chunk);
        }

        expect(accumulator.hasThinking, isTrue);

        final finalResult = accumulator.buildFinal();
        expect(
          finalResult.metadata['thinking'],
          equals('Let me think about this... I need to consider... the implications.'),
        );
      });

      test('handles empty thinking content', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(role: ChatMessageRole.model, parts: []),
          messages: const [],
          finishReason: FinishReason.stop,
          metadata: const {'thinking': ''},
          usage: null,
        );

        accumulator.add(result);

        expect(accumulator.hasThinking, isFalse);

        final finalResult = accumulator.buildFinal();
        expect(finalResult.metadata.containsKey('thinking'), isFalse);
      });

      test('handles null thinking content', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(role: ChatMessageRole.model, parts: []),
          messages: const [],
          finishReason: FinishReason.stop,
          metadata: const {'thinking': null},
          usage: null,
        );

        accumulator.add(result);

        expect(accumulator.hasThinking, isFalse);

        final finalResult = accumulator.buildFinal();
        expect(finalResult.metadata.containsKey('thinking'), isFalse);
      });
    });

    group('Safety Ratings Accumulation', () {
      test('accumulates safety ratings correctly', () {
        final chunks = [
          ChatResult<ChatMessage>(
            id: 'test-1',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.unspecified,
            metadata: const {
              'safety_ratings': [
                {'category': 'HARM_CATEGORY_HARASSMENT', 'probability': 'LOW'},
              ],
            },
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-2',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.stop,
            metadata: const {
              'safety_ratings': [
                {'category': 'HARM_CATEGORY_HATE_SPEECH', 'probability': 'NEGLIGIBLE'},
              ],
            },
            usage: null,
          ),
        ];

        for (final chunk in chunks) {
          accumulator.add(chunk);
        }

        expect(accumulator.hasSafetyRatings, isTrue);

        final finalResult = accumulator.buildFinal();
        final safetyRatings = finalResult.metadata['safety_ratings'] as List;
        expect(safetyRatings, hasLength(2));
        expect(safetyRatings[0]['category'], equals('HARM_CATEGORY_HARASSMENT'));
        expect(safetyRatings[1]['category'], equals('HARM_CATEGORY_HATE_SPEECH'));
      });

      test('handles empty safety ratings', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(role: ChatMessageRole.model, parts: []),
          messages: const [],
          finishReason: FinishReason.stop,
          metadata: const {'safety_ratings': []},
          usage: null,
        );

        accumulator.add(result);

        expect(accumulator.hasSafetyRatings, isFalse);

        final finalResult = accumulator.buildFinal();
        expect(finalResult.metadata.containsKey('safety_ratings'), isFalse);
      });

      test('handles null safety ratings', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(role: ChatMessageRole.model, parts: []),
          messages: const [],
          finishReason: FinishReason.stop,
          metadata: const {'safety_ratings': null},
          usage: null,
        );

        accumulator.add(result);

        expect(accumulator.hasSafetyRatings, isFalse);

        final finalResult = accumulator.buildFinal();
        expect(finalResult.metadata.containsKey('safety_ratings'), isFalse);
      });
    });

    group('Citation Metadata Accumulation', () {
      test('accumulates citation metadata correctly', () {
        final chunks = [
          ChatResult<ChatMessage>(
            id: 'test-1',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.unspecified,
            metadata: const {'citation_metadata': 'Source: Wikipedia'},
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-2',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.stop,
            metadata: const {'citation_metadata': 'Source: Scientific Paper'},
            usage: null,
          ),
        ];

        for (final chunk in chunks) {
          accumulator.add(chunk);
        }

        final finalResult = accumulator.buildFinal();
        expect(
          finalResult.metadata['citation_metadata'],
          equals('Source: Wikipedia; Source: Scientific Paper'),
        );
      });

      test('deduplicates citation metadata', () {
        final chunks = [
          ChatResult<ChatMessage>(
            id: 'test-1',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.unspecified,
            metadata: const {'citation_metadata': 'Source: Wikipedia'},
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-2',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.stop,
            metadata: const {'citation_metadata': 'Source: Wikipedia'},
            usage: null,
          ),
        ];

        for (final chunk in chunks) {
          accumulator.add(chunk);
        }

        final finalResult = accumulator.buildFinal();
        expect(
          finalResult.metadata['citation_metadata'],
          equals('Source: Wikipedia'),
        );
      });

      test('handles null citation metadata', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(role: ChatMessageRole.model, parts: []),
          messages: const [],
          finishReason: FinishReason.stop,
          metadata: const {'citation_metadata': null},
          usage: null,
        );

        accumulator.add(result);

        final finalResult = accumulator.buildFinal();
        expect(finalResult.metadata.containsKey('citation_metadata'), isFalse);
      });
    });

    group('General Metadata Accumulation', () {
      test('accumulates non-special metadata correctly', () {
        final chunks = [
          ChatResult<ChatMessage>(
            id: 'test-1',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.unspecified,
            metadata: const {
              'model_version': '1.0',
              'temperature': 0.7,
            },
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-2',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.stop,
            metadata: const {
              'model_version': '1.1', // Should override
              'top_p': 0.9,
            },
            usage: null,
          ),
        ];

        for (final chunk in chunks) {
          accumulator.add(chunk);
        }

        final finalResult = accumulator.buildFinal();
        expect(finalResult.metadata['model_version'], equals('1.1'));
        expect(finalResult.metadata['temperature'], equals(0.7));
        expect(finalResult.metadata['top_p'], equals(0.9));
        expect(finalResult.metadata['chunk_count'], equals(2));
      });

      test('preserves final chunk metadata correctly', () {
        final chunks = [
          ChatResult<ChatMessage>(
            id: 'test-1',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.unspecified,
            metadata: const {'request_id': 'req-1'},
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-2',
            output: const ChatMessage(role: ChatMessageRole.model, parts: []),
            messages: const [],
            finishReason: FinishReason.stop,
            metadata: const {'request_id': 'req-2'},
            usage: const LanguageModelUsage(
              promptTokens: 5,
              responseTokens: 10,
              totalTokens: 15,
            ),
          ),
        ];

        for (final chunk in chunks) {
          accumulator.add(chunk);
        }

        final finalResult = accumulator.buildFinal();
        // Should use the final chunk's metadata
        expect(finalResult.metadata['request_id'], equals('req-2'));
        expect(finalResult.usage?.totalTokens, equals(15));
        expect(finalResult.finishReason, equals(FinishReason.stop));
      });
    });

    group('Complex Accumulation Scenarios', () {
      test('handles comprehensive streaming scenario', () {
        final chunks = [
          ChatResult<ChatMessage>(
            id: 'test-1',
            output: const ChatMessage(
              role: ChatMessageRole.model,
              parts: [TextPart('The answer ')],
            ),
            messages: const [
              ChatMessage(
                role: ChatMessageRole.user,
                parts: [TextPart('What is the meaning of life?')],
              ),
            ],
            finishReason: FinishReason.unspecified,
            metadata: const {
              'thinking': 'This is a philosophical question...',
              'safety_ratings': [
                {'category': 'HARM_CATEGORY_HARASSMENT', 'probability': 'LOW'},
              ],
              'model_version': '1.5',
            },
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-2',
            output: const ChatMessage(
              role: ChatMessageRole.model,
              parts: [TextPart('is complex ')],
            ),
            messages: const [],
            finishReason: FinishReason.unspecified,
            metadata: const {
              'thinking': ' I should provide a thoughtful response.',
              'citation_metadata': 'Douglas Adams, Hitchhiker\'s Guide',
            },
            usage: null,
          ),
          ChatResult<ChatMessage>(
            id: 'test-3',
            output: const ChatMessage(
              role: ChatMessageRole.model,
              parts: [TextPart('and varies by perspective.')],
            ),
            messages: const [
              ChatMessage(
                role: ChatMessageRole.model,
                parts: [TextPart('The answer is complex and varies by perspective.')],
              ),
            ],
            finishReason: FinishReason.stop,
            metadata: const {
              'safety_ratings': [
                {'category': 'HARM_CATEGORY_HATE_SPEECH', 'probability': 'NEGLIGIBLE'},
              ],
              'model_version': '1.5-updated',
            },
            usage: const LanguageModelUsage(
              promptTokens: 20,
              responseTokens: 30,
              totalTokens: 50,
            ),
          ),
        ];

        for (final chunk in chunks) {
          accumulator.add(chunk);
        }

        expect(accumulator.accumulatedTextLength, equals(48));
        expect(accumulator.chunkCount, equals(3));
        expect(accumulator.hasThinking, isTrue);
        expect(accumulator.hasSafetyRatings, isTrue);

        final finalResult = accumulator.buildFinal();
        
        // Check accumulated text
        expect(
          finalResult.output.text,
          equals('The answer is complex and varies by perspective.'),
        );
        
        // Check accumulated messages
        expect(finalResult.messages, hasLength(2));
        expect(finalResult.messages[0].role, equals(ChatMessageRole.user));
        expect(finalResult.messages[1].role, equals(ChatMessageRole.model));
        
        // Check accumulated thinking
        expect(
          finalResult.metadata['thinking'],
          equals('This is a philosophical question... I should provide a thoughtful response.'),
        );
        
        // Check accumulated safety ratings
        final safetyRatings = finalResult.metadata['safety_ratings'] as List;
        expect(safetyRatings, hasLength(2));
        
        // Check citation metadata
        expect(
          finalResult.metadata['citation_metadata'],
          equals('Douglas Adams, Hitchhiker\'s Guide'),
        );
        
        // Check final result properties
        expect(finalResult.finishReason, equals(FinishReason.stop));
        expect(finalResult.usage?.totalTokens, equals(50));
        expect(finalResult.metadata['model_version'], equals('1.5-updated'));
        expect(finalResult.metadata['chunk_count'], equals(3));
      });

      test('handles edge case with no output text but messages', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(role: ChatMessageRole.model, parts: []),
          messages: const [
            ChatMessage(
              role: ChatMessageRole.model,
              parts: [TextPart('Tool call result')],
            ),
          ],
          finishReason: FinishReason.toolCalls,
          metadata: const {},
          usage: null,
        );

        accumulator.add(result);

        final finalResult = accumulator.buildFinal();
        expect(finalResult.output.parts, isEmpty);
        expect(finalResult.messages, hasLength(1));
        expect(finalResult.messages[0].text, equals('Tool call result'));
        expect(finalResult.finishReason, equals(FinishReason.toolCalls));
      });
    });

    group('Error Handling', () {
      test('handles malformed safety ratings by throwing type error', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(role: ChatMessageRole.model, parts: []),
          messages: const [],
          finishReason: FinishReason.stop,
          metadata: const {
            'safety_ratings': 'not_a_list', // Invalid type
          },
          usage: null,
        );

        // Should throw type error for invalid safety ratings
        expect(() => accumulator.add(result), throwsA(isA<TypeError>()));
      });

      test('handles malformed thinking content by throwing type error', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(role: ChatMessageRole.model, parts: []),
          messages: const [],
          finishReason: FinishReason.stop,
          metadata: const {
            'thinking': 123, // Invalid type
          },
          usage: null,
        );

        // Should throw type error for invalid thinking content
        expect(() => accumulator.add(result), throwsA(isA<TypeError>()));
      });
    });

    group('Multiple Build Calls', () {
      test('allows multiple buildFinal calls', () {
        final result = ChatResult<ChatMessage>(
          id: 'test-1',
          output: const ChatMessage(
            role: ChatMessageRole.model,
            parts: [TextPart('Hello')],
          ),
          messages: const [],
          finishReason: FinishReason.stop,
          metadata: const {},
          usage: null,
        );

        accumulator.add(result);

        final firstBuild = accumulator.buildFinal();
        final secondBuild = accumulator.buildFinal();

        expect(firstBuild.output.text, equals(secondBuild.output.text));
        expect(firstBuild.finishReason, equals(secondBuild.finishReason));
      });
    });
  });
}