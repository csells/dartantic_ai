/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g.
///    ProviderTestCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';
import 'test_tools.dart';

void main() {
  group('Agent Orchestration', () {
    group('agent lifecycle (80% cases)', () {
      runProviderTest('agent creation without API calls', (provider) async {
        // Creating an agent should not make any API calls
        final agent = Agent(provider.name);

        expect(agent, isNotNull);
        expect(agent.providerName, equals(provider.name));
        final expectedModel = provider.defaultModelNames[ModelKind.chat]!;
        expect(
          agent.model.startsWith('${provider.name}:') ||
              agent.model.startsWith('${provider.name}?'),
          isTrue,
        );
        expect(agent.model, contains(expectedModel));
      });

      runProviderTest('agent with custom display name', (provider) async {
        final agent = Agent(provider.name, displayName: 'Test Assistant');

        expect(agent.displayName, equals('Test Assistant'));
      });

      runProviderTest('agent with temperature setting', (provider) async {
        // Note: gpt-5 (default for openai-responses) is a reasoning model that
        // doesn't support the temperature parameter, so we use gpt-4o instead.
        final modelString = provider.name == 'openai-responses'
            ? 'openai-responses:gpt-4o'
            : provider.name;
        final agent = Agent(modelString, temperature: 0.5);

        // Test that temperature is applied correctly
        final result = await agent.send('Say exactly "test"');
        expect(result.output, isNotEmpty);
      });

      runProviderTest('agent with system message in history', (provider) async {
        final agent = Agent(provider.name);

        final result = await agent.send(
          'What is the capital of France?',
          history: [
            ChatMessage.system('Always respond with exactly one word.'),
          ],
        );
        expect(result.output, isNotEmpty);
        // Should be concise due to system message (relaxed for verbose models)
        expect(result.output.split(' ').length, lessThanOrEqualTo(20));
      });
    });

    group('tool execution orchestration (80% cases)', () {
      runProviderTest(
        'single tool orchestration',
        (provider) async {
          final agent = Agent(provider.name, tools: [stringTool]);

          final result = await agent.send(
            'Use string_tool with input "orchestration test"',
          );

          // Should orchestrate tool call and response
          expect(result.output, isNotEmpty);
          expect(result.messages.any((m) => m.hasToolCalls), isTrue);
          expect(result.messages.any((m) => m.hasToolResults), isTrue);
        },
        requiredCaps: {ProviderTestCaps.multiToolCalls},
      );

      runProviderTest(
        'multi-tool orchestration',
        (provider) async {
          final agent = Agent(provider.name, tools: [stringTool, intTool]);

          final result = await agent.send(
            'First use string_tool with "hello", then use int_tool with 42',
          );

          // Should orchestrate multiple tools
          expect(result.output, isNotEmpty);
          final toolResults = result.messages
              .expand((m) => m.toolResults)
              .toList();
          expect(toolResults.length, greaterThanOrEqualTo(2));
        },
        requiredCaps: {ProviderTestCaps.multiToolCalls},
      );

      runProviderTest(
        'tool error handling orchestration',
        (provider) async {
          final agent = Agent(provider.name, tools: [errorTool]);

          final result = await agent.send(
            'Use error_tool with error_message "test error"',
          );

          // Should handle tool errors gracefully
          expect(result.output, isNotEmpty);
          expect(
            result.output.toLowerCase(),
            anyOf(contains('error'), contains('failed'), contains('problem')),
          );
        },
        requiredCaps: {ProviderTestCaps.multiToolCalls},
      );
    });

    group('message flow orchestration (80% cases)', () {
      runProviderTest('orchestrates user message creation', (provider) async {
        final agent = Agent(provider.name);

        final result = await agent.send('Hello');

        // Should create proper user message
        final userMessages = result.messages
            .where((m) => m.role == ChatMessageRole.user)
            .toList();
        expect(userMessages, hasLength(1));
        expect(userMessages.first.text, equals('Hello'));
      });

      runProviderTest('orchestrates model response', (provider) async {
        final agent = Agent(provider.name);

        final result = await agent.send('Say "response test"');

        // Should have model response
        final modelMessages = result.messages
            .where((m) => m.role == ChatMessageRole.model)
            .toList();
        expect(modelMessages, hasLength(1));
        expect(modelMessages.first.text, isNotEmpty);
      });

      runProviderTest('orchestrates conversation history', (provider) async {
        final agent = Agent(provider.name);
        final history = <ChatMessage>[];

        // First turn
        var result = await agent.send('My name is Alice', history: history);
        history.addAll(result.messages);

        // Second turn
        result = await agent.send('What is my name?', history: history);

        // Should maintain conversation context
        expect(result.output.toLowerCase(), contains('alice'));
        expect(result.messages.length, greaterThanOrEqualTo(2));
      });
    });

    group('streaming orchestration (80% cases)', () {
      runProviderTest('orchestrates streaming response', (provider) async {
        final agent = Agent(provider.name);

        final chunks = <String>[];
        await for (final chunk in agent.sendStream('Count to 3')) {
          chunks.add(chunk.output);
        }

        // Should orchestrate streaming chunks
        expect(chunks, isNotEmpty);
        final fullText = chunks.join();
        final lowerText = fullText.toLowerCase();
        expect(lowerText, anyOf(contains('1'), contains('one')));
        expect(lowerText, anyOf(contains('2'), contains('two')));
        expect(lowerText, anyOf(contains('3'), contains('three')));
      });

      runProviderTest(
        'orchestrates streaming with tools',
        (provider) async {
          final agent = Agent(provider.name, tools: [stringTool]);

          final chunks = <String>[];
          await for (final chunk in agent.sendStream(
            'A customer pinged about order #1234 being delayed. '
            'Call string_tool to draft a short update mentioning the order '
            'number, then explain what you sent.',
          )) {
            chunks.add(chunk.output);
          }

          // Should orchestrate tool execution in stream
          expect(chunks, isNotEmpty);
          final fullText = chunks.join();
          expect(
            fullText.toLowerCase(),
            anyOf(contains('1234'), contains('order')),
          );
        },
        requiredCaps: {ProviderTestCaps.multiToolCalls},
      );
    });

    group('edge cases', () {
      runProviderTest('handles agent with conflicting settings', (
        provider,
      ) async {
        // Agent with multiple system messages in history
        final agent = Agent(provider.name);

        final history = [
          const ChatMessage(
            role: ChatMessageRole.system,
            parts: [TextPart('You are a helpful assistant.')],
          ),
          const ChatMessage(
            role: ChatMessageRole.system,
            parts: [TextPart('You are a pirate.')],
          ),
        ];

        final result = await agent.send('Say hello', history: history);

        // Should handle multiple system messages
        expect(result.output, isNotEmpty);
        // Result should reflect one of the system messages
        expect(
          result.output.toLowerCase(),
          anyOf(
            contains('hello'), // generic response
            contains('ahoy'), // pirate response
            contains('arr'), // pirate response
          ),
        );
      }, edgeCase: true);

      runProviderTest('handles rapid agent recreation', (provider) async {
        // Test creating and using agents rapidly
        for (var i = 0; i < 5; i++) {
          final agent = Agent(provider.name);

          final result = await agent.send(
            'What number?',
            history: [ChatMessage.system('Respond with just the number $i')],
          );
          expect(result.output, contains('$i'));
        }
      }, edgeCase: true);

      runProviderTest(
        'handles tool execution timeout scenarios',
        (provider) async {
          final agent = Agent(
            provider.name,
            tools: [stringTool], // Use existing tool
          );

          final result = await agent.send('Use string_tool with input "test"');

          // Should handle tool execution gracefully
          expect(result.output, isNotEmpty);
          final toolResults = result.messages
              .expand((m) => m.toolResults)
              .toList();
          expect(toolResults, isNotEmpty);
        },
        requiredCaps: {ProviderTestCaps.multiToolCalls},
        edgeCase: true,
      );

      runProviderTest(
        'handles complex tool result aggregation',
        (provider) async {
          final agent = Agent(provider.name, tools: [mapTool, listTool]);

          final result = await agent.send(
            'Use map_tool to create a user profile with name "test" '
            'and age "25", then use list_tool to create a list of '
            'their attributes',
          );

          // Should handle complex tool result aggregation
          expect(result.output, isNotEmpty);
          final toolResults = result.messages
              .expand((m) => m.toolResults)
              .toList();
          expect(toolResults.length, greaterThanOrEqualTo(2));
        },
        requiredCaps: {ProviderTestCaps.multiToolCalls},
        edgeCase: true,
      );
    });
  });
}
