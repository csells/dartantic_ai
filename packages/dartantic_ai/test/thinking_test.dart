/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';
import 'test_tools.dart';

void main() {
  // Extended timeout for thinking tests as models take longer when reasoning
  group(
    'Thinking (Extended Reasoning)',
    timeout: const Timeout(Duration(seconds: 180)),
    () {
      group('streaming with thinking (80% cases)', () {
        _runThinkingProviderTest(
          'thinking appears in metadata during streaming',
          (provider) async {
            final agent = _createAgentWithThinking(provider);

            final thinkingChunks = <String>[];
            final textChunks = <String>[];

            await for (final chunk in agent.sendStream(
              'What is 23 multiplied by 47? Show your reasoning.',
            )) {
              // Collect thinking deltas
              if (chunk.thinking != null) {
                thinkingChunks.add(chunk.thinking!);
              }

              // Collect response text
              if (chunk.output.isNotEmpty) {
                textChunks.add(chunk.output);
              }
            }

            // Should have received thinking content
            expect(
              thinkingChunks,
              isNotEmpty,
              reason: 'Should receive thinking chunks',
            );

            // Should have received response text
            expect(
              textChunks,
              isNotEmpty,
              reason: 'Should receive text response',
            );

            // Full thinking should be substantial
            final fullThinking = thinkingChunks.join();
            expect(
              fullThinking.length,
              greaterThan(10),
              reason: 'Thinking should be substantial',
            );

            // Response should contain the answer (may be formatted with comma)
            final fullResponse = textChunks.join();
            expect(
              fullResponse.replaceAll(',', ''),
              contains('1081'),
              reason: 'Should contain the correct answer',
            );
          },
          requiredCaps: {ProviderCaps.thinking},
        );

        _runThinkingProviderTest(
          'thinking accumulates through streaming',
          (provider) async {
            final agent = _createAgentWithThinking(provider);

            final thinkingChunks = <String>[];

            await for (final chunk in agent.sendStream(
              'Calculate 156 divided by 12',
            )) {
              if (chunk.thinking != null) {
                thinkingChunks.add(chunk.thinking!);
              }
            }

            // Should have received thinking chunks
            expect(
              thinkingChunks,
              isNotEmpty,
              reason: 'Should receive thinking chunks',
            );

            // Accumulated thinking should be substantial
            final fullThinking = thinkingChunks.join();
            expect(
              fullThinking.length,
              greaterThan(10),
              reason: 'Thinking should accumulate to substantial content',
            );
          },
          requiredCaps: {ProviderCaps.thinking},
        );

        _runThinkingProviderTest(
          'thinking does not appear in message parts',
          (provider) async {
            final agent = _createAgentWithThinking(provider);

            var hadMessages = false;

            await for (final chunk in agent.sendStream('Simple math: 7 + 8')) {
              // Check messages in this chunk
              for (final message in chunk.messages) {
                hadMessages = true;
                // No part should contain thinking content as separate part type
                for (final part in message.parts) {
                  // Thinking should never appear as a distinct part
                  final partType = part.runtimeType.toString();
                  expect(
                    partType,
                    isNot(contains('Thinking')),
                    reason: 'Thinking should not appear as a message part type',
                  );
                }
              }
            }

            // Should have checked at least some messages
            expect(hadMessages, true, reason: 'Should have messages to verify');
          },
          requiredCaps: {ProviderCaps.thinking},
        );

        _runThinkingProviderTest(
          'thinking works with tool calls',
          (provider) async {
            final agent = _createAgentWithThinking(
              provider,
              tools: [currentDateTimeTool],
            );

            var hadThinking = false;
            var hadToolCall = false;
            var hadText = false;

            await for (final chunk in agent.sendStream(
              'What time is it right now?',
            )) {
              if (chunk.thinking != null) hadThinking = true;

              // Check for tool calls in messages
              for (final message in chunk.messages) {
                if (message.toolCalls.isNotEmpty) hadToolCall = true;
              }

              // Check for text output
              if (chunk.output.isNotEmpty) hadText = true;
            }

            expect(hadThinking, true, reason: 'Should have thinking');
            expect(hadToolCall, true, reason: 'Should have tool call');
            expect(hadText, true, reason: 'Should have text response');
          },
          requiredCaps: {ProviderCaps.thinking, ProviderCaps.multiToolCalls},
        );
      });

      group('non-streaming with thinking (80% cases)', () {
        _runThinkingProviderTest(
          'thinking appears in result metadata for non-streaming',
          (provider) async {
            final agent = _createAgentWithThinking(provider);

            final result = await agent.send('What is 15 plus 27?');

            // Thinking should be in result
            expect(result.thinking, isNotNull, reason: 'Should have thinking');
            expect(
              result.thinking,
              isNotEmpty,
              reason: 'Thinking should not be empty',
            );
            expect(
              result.thinking!.length,
              greaterThan(10),
              reason: 'Thinking should be substantial',
            );

            // Response should contain answer
            expect(
              result.output,
              contains('42'),
              reason: 'Should contain correct answer',
            );
          },
          requiredCaps: {ProviderCaps.thinking},
        );

        _runThinkingProviderTest(
          'thinking not included in conversation history',
          (provider) async {
            final agent = _createAgentWithThinking(provider);

            final result = await agent.send('Simple question: 2+2');

            // Check all messages in result
            for (final message in result.messages) {
              for (final part in message.parts) {
                // No part should reference thinking
                final partType = part.runtimeType.toString();
                expect(
                  partType,
                  isNot(contains('Thinking')),
                  reason: 'Thinking should not appear in message parts',
                );
              }
            }

            // But thinking should be in result
            expect(result.thinking, isNotNull);
          },
          requiredCaps: {ProviderCaps.thinking},
        );
      });

      group('thinking with different question types (80% cases)', () {
        _runThinkingProviderTest(
          'thinking for mathematical reasoning',
          (provider) async {
            final agent = _createAgentWithThinking(provider);

            final result = await agent.send(
              'If a train travels 60 miles per hour for 2.5 hours, '
              'how far does it travel?',
            );

            expect(result.thinking, isNotNull);
            expect(result.thinking, isNotEmpty);

            // Should contain the answer
            expect(result.output, contains('150'));
          },
          requiredCaps: {ProviderCaps.thinking},
        );

        _runThinkingProviderTest('thinking for logical reasoning', (
          provider,
        ) async {
          final agent = _createAgentWithThinking(provider);

          final result = await agent.send(
            'If all cats are mammals, and Fluffy is a cat, '
            'what can we conclude about Fluffy?',
          );

          expect(result.thinking, isNotNull);
          expect(result.thinking, isNotEmpty);

          // Should conclude Fluffy is a mammal
          final output = result.output.toLowerCase();
          expect(output, contains('mammal'));
        }, requiredCaps: {ProviderCaps.thinking});

        _runThinkingProviderTest(
          'thinking for problem decomposition',
          (provider) async {
            final agent = _createAgentWithThinking(provider);

            final result = await agent.send(
              'How many quarters are in 5 dollars?',
            );

            expect(result.thinking, isNotNull);
            expect(result.thinking, isNotEmpty);

            // Should contain the answer
            expect(result.output, contains('20'));
          },
          requiredCaps: {ProviderCaps.thinking},
        );
      });
    },
  );
}

/// Map of provider names to thinking-capable model names.
///
/// Providers that support thinking may require specific models that have
/// the thinking capability. This map specifies which model to use for each
/// provider when testing thinking functionality.
const _thinkingModelsByProvider = {
  'openai-responses': 'gpt-5',
  'anthropic': 'claude-sonnet-4-5',
  'google': 'gemini-2.5-flash',
};

void _runThinkingProviderTest(
  String description,
  Future<void> Function(Provider provider) testFunction, {
  Set<ProviderCaps>? requiredCaps,
  bool edgeCase = false,
  Timeout? timeout,
  Set<String>? skipProviders,
}) {
  runProviderTest(
    description,
    testFunction,
    requiredCaps: requiredCaps,
    edgeCase: edgeCase,
    timeout: timeout,
    skipProviders: skipProviders,
    labelBuilder: _thinkingTestLabelBuilder,
  );
}

/// Creates an agent with thinking enabled for the given provider.
///
/// This function handles provider-specific configuration for thinking:
/// - Selects the appropriate thinking-capable model from the map
/// - Enables thinking at the Agent level
Agent _createAgentWithThinking(Provider provider, {List<Tool>? tools}) {
  final fullModelString = _thinkingModelString(provider);
  return Agent(fullModelString, tools: tools, enableThinking: true);
}

String _thinkingTestLabelBuilder(Provider provider, String defaultLabel) =>
    _thinkingModelString(provider, fallback: defaultLabel);

String _thinkingModelString(Provider provider, {String? fallback}) {
  final modelName = _thinkingModelsByProvider[provider.name];
  if (modelName == null) {
    if (fallback != null) return fallback;
    throw ArgumentError(
      'Provider ${provider.name} not configured for thinking tests',
    );
  }
  return '${provider.name}:$modelName';
}
