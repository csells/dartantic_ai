// CRITICAL TEST FAILURE INVESTIGATION PROCESS: When a test fails for a provider
// capability:
// 1. NEVER immediately disable the capability in provider definitions
// 2. ALWAYS investigate at the API level first:
//    - Test with curl to verify if the feature works at the raw API level
//    - Check the provider's official documentation
//    - Look for differences between our implementation and the API requirements
// 3. ONLY disable a capability after confirming:
//    - The API itself doesn't support the feature, OR
//    - The API has a fundamental limitation (like Together's streaming tool
//      format)
// 4. If the API supports it but our code doesn't: FIX THE IMPLEMENTATION

// ignore_for_file: avoid_dynamic_calls

import 'dart:typed_data';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';
import 'test_utils.dart';

void main() {
  group('Chat Messages', () {
    group('single turn chat', () {
      test('sends a simple message and receives response', () async {
        final agent = Agent('anthropic:claude-3-5-haiku-latest');

        final response = await agent.send(
          'Say "Hello, test!" and nothing else.',
        );
        expect(response.output, contains('Hello, test!'));
      });

      test('handles empty response gracefully', () async {
        final agent = Agent('openai:gpt-4o-mini');

        final response = await agent.send(
          'Say nothing. Return empty response.',
        );
        expect(response.output, isA<String>());
      });

      test('processes unicode and emoji correctly', () async {
        final agent = Agent('google:gemini-2.5-flash');

        final response = await agent.send('Repeat exactly: 👋 Hello 世界 🌍');
        expect(response.output, contains('👋'));
        expect(response.output, contains('世界'));
        expect(response.output, contains('🌍'));
      });

      runProviderTest(
        'handles single turn chat correctly',
        (provider) async {
          final agent = Agent(provider.name);
          final response = await agent.send('what is 7*6?');
          expect(
            response.output,
            contains('42'),
            reason: 'Provider ${provider.name} should respond correctly',
          );
        },
        requiredCaps: {ProviderCaps.chat},
        timeout: const Timeout(Duration(minutes: 3)),
      );
    });

    group('multi turn chat', () {
      test('maintains conversation history', () async {
        final agent = Agent('anthropic:claude-3-5-haiku-latest');
        final messages = <ChatMessage>[];

        var response = await agent.send(
          'My name is Alice. Remember it.',
          history: messages,
        );
        expect(response.output.toLowerCase(), contains('alice'));

        // Validate the returned messages
        validateMessageHistory(response.messages);

        // Add to history
        messages.add(
          const ChatMessage(
            role: ChatMessageRole.user,
            parts: [TextPart('My name is Alice. Remember it.')],
          ),
        );
        messages.add(
          ChatMessage(
            role: ChatMessageRole.model,
            parts: [TextPart(response.output)],
          ),
        );

        // Follow up question
        response = await agent.send('What is my name?', history: messages);
        expect(response.output.toLowerCase(), contains('alice'));

        // Validate full conversation history
        final fullHistory = [...messages, ...response.messages];
        validateMessageHistory(fullHistory);
      });

      test('handles role transitions correctly', () async {
        final agent = Agent('openai:gpt-4o-mini');

        final response = await agent.send(
          'Hello',
          history: [
            ChatMessage.system(
              'You are a helpful assistant that always includes the word '
              '"indeed" in responses.',
            ),
          ],
        );
        expect(response.output.toLowerCase(), contains('indeed'));

        // Validate that system prompt + messages follow correct pattern
        validateMessageHistory(response.messages);
      });

      test('accumulates multiple exchanges', () async {
        final agent = Agent('google:gemini-2.5-flash');
        final messages = <ChatMessage>[];

        // First exchange
        var response = await agent.send('Count to 1', history: messages);
        messages.add(
          const ChatMessage(
            role: ChatMessageRole.user,
            parts: [TextPart('Count to 1')],
          ),
        );
        messages.add(
          ChatMessage(
            role: ChatMessageRole.model,
            parts: [TextPart(response.output)],
          ),
        );

        // Second exchange
        response = await agent.send('Now count to 2', history: messages);
        messages.add(
          const ChatMessage(
            role: ChatMessageRole.user,
            parts: [TextPart('Now count to 2')],
          ),
        );
        messages.add(
          ChatMessage(
            role: ChatMessageRole.model,
            parts: [TextPart(response.output)],
          ),
        );

        // Verify history is maintained
        expect(messages, hasLength(4));
        expect(messages[0].role, equals(ChatMessageRole.user));
        expect(messages[1].role, equals(ChatMessageRole.model));

        // Validate full conversation history follows correct pattern
        validateMessageHistory(messages);
        expect(messages[2].role, equals(ChatMessageRole.user));
        expect(messages[3].role, equals(ChatMessageRole.model));
      });

      runProviderTest(
        'handles multi-turn conversation correctly',
        (provider) async {
          final agent = Agent(provider.name);
          final messages = <ChatMessage>[];

          var response = await agent.send(
            'My favorite color is purple. Remember that.',
            history: messages,
          );

          messages.add(
            const ChatMessage(
              role: ChatMessageRole.user,
              parts: [TextPart('My favorite color is purple. Remember that.')],
            ),
          );
          messages.add(
            ChatMessage(
              role: ChatMessageRole.model,
              parts: [TextPart(response.output)],
            ),
          );

          response = await agent.send(
            'What is my favorite color?',
            history: messages,
          );

          expect(
            response.output.toLowerCase(),
            contains('purple'),
            reason:
                'Provider ${provider.name} should remember '
                'conversation context',
          );
        },
        requiredCaps: {ProviderCaps.chat},
        timeout: const Timeout(Duration(minutes: 3)),
      );
    });

    group('streaming', () {
      test('streams response chunks', () async {
        final agent = Agent('anthropic:claude-3-5-haiku-latest');

        final chunks = <String>[];
        await for (final chunk in agent.sendStream(
          'Count slowly from 1 to 3',
        )) {
          chunks.add(chunk.output);
        }

        expect(chunks, isNotEmpty);
        final fullResponse = chunks.join();
        expect(fullResponse, anyOf(contains('1'), contains('one')));
        expect(fullResponse, anyOf(contains('2'), contains('two')));
        expect(fullResponse, anyOf(contains('3'), contains('three')));
      });

      test('handles empty chunks', () async {
        final agent = Agent('openai:gpt-4o-mini');

        final chunks = <String>[];
        await for (final chunk in agent.sendStream('Say "test"')) {
          chunks.add(chunk.output);
        }

        // Should have received some chunks
        expect(chunks, isNotEmpty);
        // But individual chunks might be empty
        expect(chunks.join().toLowerCase(), contains('test'));
      });

      runProviderTest(
        'handles streaming correctly',
        (provider) async {
          final agent = Agent(provider.name);

          final chunks = <String>[];
          await for (final chunk in agent.sendStream('Count from 1 to 3')) {
            chunks.add(chunk.output);
          }

          expect(
            chunks,
            isNotEmpty,
            reason: 'Provider ${provider.name} should stream chunks',
          );

          final fullResponse = chunks.join();
          expect(
            fullResponse,
            allOf([contains('1'), contains('2'), contains('3')]),
            reason: 'Provider ${provider.name} should stream complete response',
          );
        },
        requiredCaps: {ProviderCaps.chat},
        timeout: const Timeout(Duration(minutes: 3)),
      );
    });

    group('error handling', () {
      test('handles invalid model names', () async {
        expect(() => Agent('invalid:model-name'), throwsA(isA<Exception>()));
      });

      test('handles malformed messages gracefully', () async {
        final agent = Agent('anthropic:claude-3-5-haiku-latest');

        // Empty prompt should still work
        final response = await agent.send('Say "test"');
        expect(response.output, isA<String>());
      });
    });

    group('all providers - comprehensive test', () {
      runProviderTest(
        'basic chat works',
        (provider) async {
          final agent = Agent(provider.name);

          final response = await agent.send('what is 7*6?');

          expect(
            response.output.toLowerCase(),
            contains('42'),
            reason: 'Provider ${provider.name} should respond correctly',
          );
        },
        requiredCaps: {ProviderCaps.chat},
        timeout: const Timeout(Duration(seconds: 30)),
      );
    });

    group('JSON serialization', () {
      test('serializes and deserializes simple text messages', () {
        final message = ChatMessage.user('Hello, world!');
        final json = message.toJson();
        final deserialized = ChatMessage.fromJson(json);

        expect(deserialized.role, equals(ChatMessageRole.user));
        expect(deserialized.text, equals('Hello, world!'));
        expect(deserialized.parts.length, equals(1));
        expect(deserialized.parts[0], isA<TextPart>());
        expect(
          (deserialized.parts[0] as TextPart).text,
          equals('Hello, world!'),
        );
        expect(deserialized.metadata, isEmpty);
      });

      test('serializes and deserializes messages with all roles', () {
        final systemMsg = ChatMessage.system('System prompt');
        final userMsg = ChatMessage.user('User input');
        final modelMsg = ChatMessage.model('Model response');

        // Round trip each message
        for (final msg in [systemMsg, userMsg, modelMsg]) {
          final json = msg.toJson();
          final deserialized = ChatMessage.fromJson(json);
          expect(deserialized.role, equals(msg.role));
          expect(deserialized.text, equals(msg.text));
        }
      });

      test('serializes and deserializes messages with metadata', () {
        final metadata = {
          'timestamp': 1234567890,
          'userId': 'test-user',
          'nested': {'key': 'value'},
          'array': [1, 2, 3],
          'boolean': true,
        };

        final message = ChatMessage(
          role: ChatMessageRole.user,
          parts: const [TextPart('Test message')],
          metadata: metadata,
        );

        final json = message.toJson();
        final deserialized = ChatMessage.fromJson(json);

        expect(deserialized.metadata['timestamp'], equals(1234567890));
        expect(deserialized.metadata['userId'], equals('test-user'));
        expect(deserialized.metadata['nested'], isA<Map>());
        expect(deserialized.metadata['nested']['key'], equals('value'));
        expect(deserialized.metadata['array'], equals([1, 2, 3]));
        expect(deserialized.metadata['boolean'], isTrue);
      });

      test('serializes and deserializes messages with multiple text parts', () {
        const message = ChatMessage(
          role: ChatMessageRole.model,
          parts: [
            TextPart('First part. '),
            TextPart('Second part. '),
            TextPart('Third part.'),
          ],
        );

        final json = message.toJson();
        final deserialized = ChatMessage.fromJson(json);

        expect(deserialized.parts.length, equals(3));
        expect(
          deserialized.text,
          equals('First part. Second part. Third part.'),
        );
        expect(deserialized.parts.every((p) => p is TextPart), isTrue);
      });

      test('serializes and deserializes data parts', () {
        final bytes = Uint8List.fromList([
          0x89,
          0x50,
          0x4E,
          0x47,
        ]); // PNG header
        final dataPart = DataPart(
          bytes,
          mimeType: 'image/png',
          name: 'test.png',
        );

        final message = ChatMessage(
          role: ChatMessageRole.user,
          parts: [dataPart],
        );

        final json = message.toJson();
        final deserialized = ChatMessage.fromJson(json);

        expect(deserialized.parts.length, equals(1));
        final deserializedPart = deserialized.parts[0] as DataPart;
        expect(deserializedPart.bytes, equals(bytes));
        expect(deserializedPart.mimeType, equals('image/png'));
        expect(deserializedPart.name, equals('test.png'));
      });

      test('serializes and deserializes link parts', () {
        final linkPart = LinkPart(
          Uri.parse('https://example.com/image.jpg'),
          mimeType: 'image/jpeg',
          name: 'example.jpg',
        );

        final message = ChatMessage(
          role: ChatMessageRole.user,
          parts: [linkPart],
        );

        final json = message.toJson();
        final deserialized = ChatMessage.fromJson(json);

        expect(deserialized.parts.length, equals(1));
        final deserializedPart = deserialized.parts[0] as LinkPart;
        expect(
          deserializedPart.url.toString(),
          equals('https://example.com/image.jpg'),
        );
        expect(deserializedPart.mimeType, equals('image/jpeg'));
        expect(deserializedPart.name, equals('example.jpg'));
      });

      test('serializes and deserializes tool call parts', () {
        const toolCall = ToolPart.call(
          id: 'call_123',
          name: 'get_weather',
          arguments: {
            'location': 'San Francisco',
            'units': 'celsius',
            'details': true,
          },
        );

        const message = ChatMessage(
          role: ChatMessageRole.model,
          parts: [toolCall],
        );

        final json = message.toJson();
        final deserialized = ChatMessage.fromJson(json);

        expect(deserialized.parts.length, equals(1));
        expect(deserialized.hasToolCalls, isTrue);
        expect(deserialized.toolCalls.length, equals(1));

        final deserializedCall = deserialized.parts[0] as ToolPart;
        expect(deserializedCall.kind, equals(ToolPartKind.call));
        expect(deserializedCall.id, equals('call_123'));
        expect(deserializedCall.name, equals('get_weather'));
        expect(
          deserializedCall.arguments?['location'],
          equals('San Francisco'),
        );
        expect(deserializedCall.arguments?['units'], equals('celsius'));
        expect(deserializedCall.arguments?['details'], isTrue);
      });

      test('serializes and deserializes tool result parts', () {
        const toolResult = ToolPart.result(
          id: 'call_123',
          name: 'get_weather',
          result: {'temperature': 22.5, 'condition': 'sunny', 'humidity': 65},
        );

        const message = ChatMessage(
          role: ChatMessageRole.user,
          parts: [toolResult],
        );

        final json = message.toJson();
        final deserialized = ChatMessage.fromJson(json);

        expect(deserialized.parts.length, equals(1));
        expect(deserialized.hasToolResults, isTrue);
        expect(deserialized.toolResults.length, equals(1));

        final deserializedResult = deserialized.parts[0] as ToolPart;
        expect(deserializedResult.kind, equals(ToolPartKind.result));
        expect(deserializedResult.id, equals('call_123'));
        expect(deserializedResult.name, equals('get_weather'));
        expect(deserializedResult.result['temperature'], equals(22.5));
        expect(deserializedResult.result['condition'], equals('sunny'));
        expect(deserializedResult.result['humidity'], equals(65));
      });

      test('serializes and deserializes complex mixed messages', () {
        const message = ChatMessage(
          role: ChatMessageRole.model,
          parts: [
            TextPart('Here is the weather information: '),
            ToolPart.call(
              id: 'call_456',
              name: 'get_weather',
              arguments: {'location': 'Tokyo'},
            ),
            TextPart(' and the temperature conversion: '),
            ToolPart.call(
              id: 'call_789',
              name: 'convert_temp',
              arguments: {'value': 25, 'from': 'C', 'to': 'F'},
            ),
          ],
          metadata: {'requestId': 'req_123', 'version': 2},
        );

        final json = message.toJson();
        final deserialized = ChatMessage.fromJson(json);

        expect(deserialized.role, equals(ChatMessageRole.model));
        expect(deserialized.parts.length, equals(4));
        expect(deserialized.hasToolCalls, isTrue);
        expect(deserialized.toolCalls.length, equals(2));
        expect(deserialized.metadata['requestId'], equals('req_123'));
        expect(deserialized.metadata['version'], equals(2));

        // Verify order and content of parts
        expect(deserialized.parts[0], isA<TextPart>());
        expect(
          (deserialized.parts[0] as TextPart).text,
          equals('Here is the weather information: '),
        );

        expect(deserialized.parts[1], isA<ToolPart>());
        expect((deserialized.parts[1] as ToolPart).name, equals('get_weather'));

        expect(deserialized.parts[2], isA<TextPart>());
        expect(
          (deserialized.parts[2] as TextPart).text,
          equals(' and the temperature conversion: '),
        );

        expect(deserialized.parts[3], isA<ToolPart>());
        expect(
          (deserialized.parts[3] as ToolPart).name,
          equals('convert_temp'),
        );
      });

      test('handles edge cases in serialization', () {
        // Empty parts list
        var message = const ChatMessage(role: ChatMessageRole.user, parts: []);
        var json = message.toJson();
        var deserialized = ChatMessage.fromJson(json);
        expect(deserialized.parts, isEmpty);
        expect(deserialized.text, equals(''));

        // Special characters in text
        message = ChatMessage.user(
          'Special chars: "quotes" \'single\' \n\t\r \\ unicode: 🎉',
        );
        json = message.toJson();
        deserialized = ChatMessage.fromJson(json);
        expect(
          deserialized.text,
          equals('Special chars: "quotes" \'single\' \n\t\r \\ unicode: 🎉'),
        );

        // Null metadata values
        message = const ChatMessage(
          role: ChatMessageRole.model,
          parts: [TextPart('Test')],
          metadata: {'nullValue': null, 'normalValue': 'test'},
        );
        json = message.toJson();
        deserialized = ChatMessage.fromJson(json);
        expect(deserialized.metadata['nullValue'], isNull);
        expect(deserialized.metadata['normalValue'], equals('test'));

        // Tool call with empty arguments
        const toolCall = ToolPart.call(
          id: 'empty_call',
          name: 'no_args_function',
          arguments: {},
        );
        message = const ChatMessage(
          role: ChatMessageRole.model,
          parts: [toolCall],
        );
        json = message.toJson();
        deserialized = ChatMessage.fromJson(json);
        expect((deserialized.parts[0] as ToolPart).arguments, isEmpty);
        expect((deserialized.parts[0] as ToolPart).argumentsRaw, equals('{}'));
      });

      test(
        'preserves exact structure through multiple serialization cycles',
        () {
          final originalMessage = ChatMessage(
            role: ChatMessageRole.model,
            parts: [
              const TextPart('Processing your request...'),
              const ToolPart.call(
                id: 'multi_cycle_1',
                name: 'complex_function',
                arguments: {
                  'nested': {
                    'deep': {'value': 42},
                    'array': [
                      1,
                      'two',
                      {'three': 3},
                    ],
                  },
                  'unicode': '测试 🚀',
                },
              ),
              DataPart(
                Uint8List.fromList([1, 2, 3, 4, 5]),
                mimeType: 'application/octet-stream',
                name: 'data.bin',
              ),
              LinkPart(
                Uri.parse('https://example.com/resource?query=value&other=123'),
                mimeType: 'text/html',
                name: 'webpage.html',
              ),
              const ToolPart.result(
                id: 'multi_cycle_1',
                name: 'complex_function',
                result: [
                  'array',
                  'result',
                  {'with': 'object'},
                ],
              ),
            ],
            metadata: {
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'flags': const ['important', 'reviewed'],
              'score': 0.95,
            },
          );

          // First cycle
          var json = originalMessage.toJson();
          final deserialized = ChatMessage.fromJson(json);

          // Second cycle
          json = deserialized.toJson();
          final secondDeserialized = ChatMessage.fromJson(json);

          // Third cycle
          json = secondDeserialized.toJson();
          final thirdDeserialized = ChatMessage.fromJson(json);

          // All should be equal
          expect(deserialized, equals(originalMessage));
          expect(secondDeserialized, equals(originalMessage));
          expect(thirdDeserialized, equals(originalMessage));

          // Verify complex nested structure is preserved
          final toolCallArgs =
              (thirdDeserialized.parts[1] as ToolPart).arguments;
          expect(toolCallArgs!['nested']['deep']['value'], equals(42));
          expect(toolCallArgs['nested']?['array']?[2]?['three'], equals(3));
          expect(toolCallArgs['unicode'], equals('测试 🚀'));
        },
      );
    });
  });
}
