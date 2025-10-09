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
// 5. LET EXCEPTIONS BUBBLE UP: Do not add defensive checks or try-catch blocks.
//    Missing API keys, network errors, and provider issues should fail loudly
//    so they can be identified and fixed immediately.

// ignore_for_file: avoid_dynamic_calls

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';
import 'test_tools.dart';
import 'test_utils.dart';

void main() {
  group('Tool Calling', () {
    group('single tool calls', () {
      test('calls a simple string tool', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [stringTool]);

        final response = await agent.send(
          'Use the string_tool with input "hello"',
        );

        // Check that tool was executed and result is in messages
        final toolResults = response.messages
            .expand((msg) => msg.toolResults)
            .toList();
        expect(toolResults, hasLength(1));
        expect(toolResults.first.result, equals('String result: hello'));
      });

      test('calls a tool with numeric return', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [intTool]);

        final response = await agent.send('Use the int_tool with value 42');

        // Check that tool was executed and result is in messages
        final toolResults = response.messages
            .expand((msg) => msg.toolResults)
            .toList();
        expect(toolResults, hasLength(1));
        final result = toolResults.first.result;
        // Tool result may be serialized as string or kept as int
        expect(
          result == 42 || result == '42',
          isTrue,
          reason: 'Expected 42 or "42", got $result (${result.runtimeType})',
        );
      });

      test('calls a tool returning a map', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [mapTool]);
        final response = await agent.send(
          'Use the map_tool with key "name" and value "test"',
        );

        // Check that tool was executed and result is in messages
        final toolResults = response.messages
            .expand((msg) => msg.toolResults)
            .toList();
        expect(toolResults, hasLength(1));
        final result = toolResults.first.result;
        // Result might be serialized as string or kept as map
        if (result is String) {
          // If serialized as string, parse as JSON
          expect(result, contains('test'));
          expect(result, contains('map_result'));
        } else {
          final resultMap = result as Map<String, dynamic>;
          expect(resultMap['name'], equals('test'));
          expect(resultMap['type'], equals('map_result'));
        }
      });

      // Moved to edge cases section

      runProviderTest(
        'handles single tool calls correctly',
        (provider) async {
          final agent = Agent(provider.name, tools: [stringTool]);

          final response = await agent.send(
            'Use the string_tool with input "test ${provider.name}"',
          );

          // Check that tool was executed and result is in messages
          final toolResults = response.messages
              .expand((msg) => msg.toolResults)
              .toList();
          expect(
            toolResults,
            isNotEmpty,
            reason: 'Provider ${provider.name} should execute the tool',
          );

          // Check all results are correct (provider might call multiple times)
          for (final tr in toolResults) {
            expect(
              tr.result,
              equals('String result: test ${provider.name}'),
              reason: 'Provider ${provider.name} should pass correct arguments',
            );
          }

          // Response should mention the tool result
          expect(
            response.output.toLowerCase(),
            anyOf(
              contains('test ${provider.name}'),
              contains('string_tool'),
              contains('string result'),
            ),
            reason: 'Provider ${provider.name} should reference tool result',
          );
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
      );
    });

    group('multiple tool calls', () {
      test('calls multiple tools in sequence', () async {
        final agent = Agent(
          'openai:gpt-4o-mini',
          tools: [multiStepTool1, multiStepTool2],
        );

        final response = await agent.send(
          'First call step1 with input "hello", '
          'then call step2 with the result',
        );

        // Check that both tools were executed and results are in messages
        final toolResults = response.messages
            .expand((msg) => msg.toolResults)
            .toList();
        expect(toolResults, hasLength(2));
        expect(toolResults[0].result, equals('Step 1 processed: hello'));
        expect(toolResults[1].result, contains('Step 2 processed:'));

        // Validate message history follows correct pattern
        validateMessageHistory(response.messages);
      });

      test('calls multiple independent tools', () async {
        final agent = Agent(
          'openai:gpt-4o-mini',
          tools: [stringTool, intTool, boolTool],
        );

        final response = await agent.send(
          'Call string_tool with "test", int_tool with 100, '
          'and bool_tool with true',
        );

        // Check that all three tools were executed and results are in messages
        final toolResults = response.messages
            .expand((msg) => msg.toolResults)
            .toList();
        expect(toolResults, hasLength(3));

        // Check for specific results (order may vary)
        final results = toolResults.map((tr) => tr.result).toList();
        expect(results, contains('String result: test'));
        // Tool results may be serialized as strings
        expect(results.any((r) => r == 100 || r == '100'), isTrue);
        expect(results.any((r) => r == true || r == 'true'), isTrue);

        // Validate message history follows correct pattern
        validateMessageHistory(response.messages);
      });

      test('calls same tool multiple times with different arguments', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [weatherTool]);

        final response = await agent.send(
          'What is the weather in Boston and New York?',
        );

        // Check that the tool was called twice
        final toolResults = response.messages
            .expand((msg) => msg.toolResults)
            .toList();
        expect(toolResults, hasLength(2));

        // Check for specific results (order may vary)
        final results = toolResults.map((tr) => tr.result).toList();
        expect(results.any((r) => r.contains('Boston')), isTrue);
        expect(results.any((r) => r.contains('New York')), isTrue);
        expect(results.any((r) => r.contains('45°F')), isTrue); // Boston temp
        expect(results.any((r) => r.contains('52°F')), isTrue); // New York temp
      });

      test('calls same tool multiple times with same arguments', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [stringTool]);

        // Some providers might call the same tool multiple times with same args
        // We should handle this gracefully
        final response = await agent.send(
          'Call string_tool twice with input "repeat test"',
        );

        // Should have at least one tool result
        final toolResults = response.messages
            .expand((msg) => msg.toolResults)
            .toList();
        expect(toolResults, isNotEmpty);

        // All results should be correct
        for (final tr in toolResults) {
          if (tr.name == 'string_tool') {
            expect(tr.result, equals('String result: repeat test'));
          }
        }
      });

      runProviderTest(
        'handles multiple different tools',
        (provider) async {
          final agent = Agent(provider.name, tools: [stringTool, intTool]);

          final response = await agent.send(
            'Customer onboarding requires two steps. '
            'First, call string_tool to produce the text '
            '"Welcome message for ${provider.name}". '
            'Second, call int_tool with the value 42 to record the '
            'total number of welcome packets prepared. After running both '
            'tools, summarise what you did.',
          );

          // Check that both tools were executed
          final toolResults = response.messages
              .expand((msg) => msg.toolResults)
              .toList();
          expect(
            toolResults,
            hasLength(2),
            reason: 'Provider ${provider.name} should execute both tools',
          );

          // Check for specific results (order may vary)
          final results = toolResults.map((tr) => tr.result).toList();
          expect(
            results,
            contains('String result: Welcome message for ${provider.name}'),
            reason:
                'Provider ${provider.name} should execute '
                'string_tool correctly',
          );
          expect(
            results.any((r) => r == 42 || r == '42'),
            isTrue,
            reason:
                'Provider ${provider.name} should execute int_tool correctly',
          );

          // Validate message history follows correct pattern
          validateMessageHistory(response.messages);
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
      );

      runProviderTest(
        'handles same tool multiple times with different args',
        (provider) async {
          final agent = Agent(provider.name, tools: [weatherTool]);

          final response = await agent.send(
            'What is the weather in Boston and in Los Angeles?',
          );

          // Should have called weather tool twice
          final toolResults = response.messages
              .expand((msg) => msg.toolResults)
              .toList();
          expect(
            toolResults,
            hasLength(greaterThanOrEqualTo(2)),
            reason:
                'Provider ${provider.name} should call weather tool at least '
                'twice',
          );

          // Check for results
          final results = toolResults.map((tr) => tr.result).toList();
          final allResults = results.join(' ');
          expect(
            allResults.toLowerCase(),
            contains('boston'),
            reason: 'Provider ${provider.name} should get Boston weather',
          );
          expect(
            allResults.toLowerCase(),
            contains('los angeles'),
            reason: 'Provider ${provider.name} should get LA weather',
          );
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
      );

      runProviderTest(
        'handles same tool with same args multiple times',
        (provider) async {
          final agent = Agent(provider.name, tools: [stringTool]);

          // Ask it to call the same tool multiple times with same args
          final response = await agent.send(
            'Call string_tool three times with input '
            '"repeat ${provider.name}"',
          );

          // Should have at least one tool result
          final toolResults = response.messages
              .expand((msg) => msg.toolResults)
              .toList();
          expect(
            toolResults,
            isNotEmpty,
            reason:
                'Provider ${provider.name} should execute tool at least once',
          );

          // All results should be correct
          for (final tr in toolResults) {
            if (tr.name == 'string_tool') {
              expect(
                tr.result,
                equals('String result: repeat ${provider.name}'),
                reason:
                    'Provider ${provider.name} tool results should be correct',
              );
            }
          }

          // The provider might call it 1, 2, 3 or more times - all are valid
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
      );
    });

    // Edge cases moved to dedicated section at bottom
    group('edge cases (limited providers)', () {
      runProviderTest(
        'handles null return values',
        (provider) async {
          final agent = Agent(provider.name, tools: [nullTool]);
          final response = await agent.send('Call the null_tool');
          expect(response.output, isA<String>());
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        edgeCase: true,
      );

      runProviderTest(
        'handles empty string returns',
        (provider) async {
          final agent = Agent(provider.name, tools: [emptyStringTool]);
          final response = await agent.send('Call the empty_string_tool');
          expect(response.output, isA<String>());
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        edgeCase: true,
      );

      runProviderTest(
        'handles very long string returns',
        (provider) async {
          final agent = Agent(provider.name, tools: [veryLongStringTool]);
          final response = await agent.send(
            'show the result of calling very_long_string_tool with '
            'repeat_count 10',
          );
          expect(
            response.output.toLowerCase(),
            anyOf(
              contains('lorem ipsum'),
              contains('long string'),
              contains('text'),
              contains('repeated'),
            ),
          );
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        edgeCase: true,
      );

      runProviderTest(
        'handles unicode in tool results',
        (provider) async {
          final agent = Agent(provider.name, tools: [unicodeTool]);
          final response = await agent.send('Call the unicode_tool');
          expect(response.output, isNotEmpty);

          final toolResults = response.messages
              .expand((msg) => msg.toolResults)
              .toList();
          expect(toolResults, isNotEmpty);
          expect(toolResults.first.result, contains('👋'));
          expect(toolResults.first.result, contains('世界'));
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        edgeCase: true,
      );

      runProviderTest(
        'handles special characters in tool results',
        (provider) async {
          final agent = Agent(provider.name, tools: [specialCharsTool]);
          final response = await agent.send('Call the special_chars_tool');
          expect(
            response.output.toLowerCase(),
            anyOf(
              contains('line'),
              contains('special'),
              contains('character'),
              contains('escape'),
              contains('tab'),
              contains('quote'),
            ),
          );
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        edgeCase: true,
      );

      runProviderTest(
        'handles no-params tools',
        (provider) async {
          final agent = Agent(provider.name, tools: [noParamsTool]);

          final response = await agent.send('Call the no_params_tool');
          final toolResults = response.messages
              .expand((msg) => msg.toolResults)
              .toList();
          expect(toolResults, isNotEmpty);
          for (final tr in toolResults) {
            expect(tr.result, equals('Called with no parameters'));
          }
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        edgeCase: true,
      );

      runProviderTest(
        'handles missing required parameters',
        (provider) async {
          final agent = Agent(provider.name, tools: [strictTypeTool]);

          final response = await agent.send(
            'Call strict_type_tool but only provide string_param "test"',
          );
          expect(response.output, isA<String>());
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        edgeCase: true,
      );

      runProviderTest(
        'handles tool with no parameters',
        (provider) async {
          final agent = Agent(provider.name, tools: [noParamsTool]);
          final response = await agent.send('Call the no_params_tool');
          final toolResults = response.messages
              .expand((msg) => msg.toolResults)
              .toList();
          expect(toolResults, hasLength(1));
          expect(toolResults.first.result, equals('Called with no parameters'));
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        edgeCase: true,
      );
    });

    group('error handling', () {
      test('handles tool execution errors gracefully', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [errorTool]);

        // Agent should handle the error and report it
        final response = await agent.send(
          'Call error_tool with error_message "Test error"',
        );
        expect(
          response.output.toLowerCase(),
          anyOf(contains('error'), contains('failed'), contains('exception')),
        );
      });

      // Moved to edge cases section

      test('rejects tools on unsupported providers', () async {
        // Per design, Agent does NOT validate provider capabilities
        // Providers themselves should throw if they don't support tools
        final agent = Agent(
          'mistral:mistral-small-latest',
          tools: [stringTool],
        );

        // The error will come when trying to use the agent, not at creation
        expect(() => agent.send('Use the string_tool'), throwsException);
      });

      runProviderTest(
        'handle tool errors gracefully',
        (provider) async {
          final agent = Agent(provider.name, tools: [errorTool]);

          // Agent should handle the error and report it
          final response = await agent.send(
            'Call error_tool with error_message "Test error for '
            '${provider.name}"',
          );

          // The agent should handle the error gracefully
          expect(
            response.output.toLowerCase(),
            anyOf(
              contains('error'),
              contains('failed'),
              contains('exception'),
              contains('problem'),
            ),
            reason:
                'Provider ${provider.name} should report tool errors '
                'gracefully',
          );
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        // TODO: Remove once we migrate off google_generative_ai (issue #6)
        skipProviders: {'google', 'google-openai'},
        timeout: const Timeout(Duration(minutes: 3)),
      );
    });

    group('streaming with tools', () {
      test('streams tool call results', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [stringTool]);

        final chunks = <String>[];
        await for (final chunk in agent.sendStream(
          'Use string_tool with input "streaming test"',
        )) {
          chunks.add(chunk.output);
        }

        final fullResponse = chunks.join();
        // Response should mention the tool result or input
        expect(
          fullResponse.toLowerCase(),
          anyOf(contains('streaming test'), contains('string_tool')),
        );
      });

      runProviderTest(
        'stream tool calls correctly',
        (provider) async {
          final agent = Agent(provider.name, tools: [stringTool]);

          final chunks = <String>[];
          await for (final chunk in agent.sendStream(
            'We owe customer support a quick update. Use string_tool to repeat '
            'the phrase "Status update for ${provider.name}" and share the '
            'result with me as you stream the response.',
          )) {
            chunks.add(chunk.output);
          }

          final fullResponse = chunks.join();
          // Every provider should successfully stream and use the tool
          expect(fullResponse, isNotEmpty);
          expect(
            fullResponse.toLowerCase(),
            anyOf(contains('status update'), contains(provider.name)),
            reason: 'Provider ${provider.name} failed to stream tool results',
          );
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
        // TODO: Remove once we migrate off google_generative_ai (issue #6)
        skipProviders: {'google'},
        timeout: const Timeout(Duration(minutes: 3)),
      );

      test('streams multiple tool calls', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [stringTool, intTool]);

        final chunks = <String>[];
        final messages = <ChatMessage>[];
        await for (final chunk in agent.sendStream(
          'Call string_tool with "test" and int_tool with 99',
        )) {
          chunks.add(chunk.output);
          messages.addAll(chunk.messages);
        }

        final fullResponse = chunks.join();
        // Response should mention the tool results or inputs
        expect(
          fullResponse.toLowerCase(),
          anyOf(contains('test'), contains('string_tool')),
        );
        expect(
          fullResponse.toLowerCase(),
          anyOf(contains('99'), contains('int_tool')),
        );

        // Validate message history follows correct pattern
        validateMessageHistory(messages);
      });
    });

    group('tool result integration', () {
      test('integrates tool results into message history', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [stringTool]);

        final response = await agent.send(
          'Call string_tool with "hello" and tell me what it returned',
        );

        // Check that the tool was called
        final toolResults = response.messages
            .expand((msg) => msg.toolResults)
            .toList();
        expect(toolResults, hasLength(1));
        expect(toolResults.first.result, equals('String result: hello'));

        // Response should mention the result
        expect(
          response.output.toLowerCase(),
          anyOf(contains('returned'), contains('result'), contains('output')),
        );
      });

      test('handles tool results in conversation context', () async {
        final agent = Agent('openai:gpt-4o-mini', tools: [mapTool]);
        final messages = [
          const ChatMessage(
            role: ChatMessageRole.user,
            parts: [TextPart('Use map_tool with key "color" and value "blue"')],
          ),
        ];

        var response = await agent.send(
          'Use map_tool with key "color" and value "blue"',
        );

        // Add response to history
        messages.add(
          ChatMessage(
            role: ChatMessageRole.model,
            parts: [TextPart(response.output)],
          ),
        );

        // Follow up about the tool result
        messages.add(
          const ChatMessage(
            role: ChatMessageRole.user,
            parts: [TextPart('What was the value for the color key?')],
          ),
        );

        response = await agent.send(
          'What was the value for the color key?',
          history: messages,
        );
        expect(response.output.toLowerCase(), contains('blue'));
      });

      runProviderTest(
        'integrate tool results into messages correctly',
        (provider) async {
          final agent = Agent(provider.name, tools: [stringTool]);

          final response = await agent.send(
            'return the result of the string_tool with '
            '"hello ${provider.name}"',
          );

          // Check that the tool was called
          final toolResults = response.messages
              .expand((msg) => msg.toolResults)
              .toList();
          expect(
            toolResults,
            hasLength(1),
            reason: 'Provider ${provider.name} should execute the tool',
          );
          expect(
            toolResults.first.result,
            equals('String result: hello ${provider.name}'),
            reason:
                'Provider ${provider.name} should return correct tool '
                'result',
          );

          // Response should mention the result
          expect(
            response.output.toLowerCase(),
            anyOf(
              contains('returned'),
              contains('result'),
              contains('output'),
              contains('hello ${provider.name}'),
              contains('string result'),
            ),
            reason:
                'Provider ${provider.name} should mention the tool '
                'result in response',
          );
        },
        requiredCaps: {ProviderCaps.multiToolCalls},

        timeout: const Timeout(Duration(minutes: 3)),
      );
    });

    group('all providers - tool support', () {
      runProviderTest(
        'tool calling works across supporting providers',
        (provider) async {
          final testTool = stringTool;

          final agent = Agent(provider.name, tools: [testTool]);

          final response = await agent.send(
            'Show the result of using string_tool with input "provider test"',
          );

          // Response should mention the tool result or input
          expect(
            response.output.toLowerCase(),
            anyOf(contains('provider test'), contains('string_tool')),
            reason: 'Provider ${provider.name} should execute tool correctly',
          );

          // Verify tool was actually called
          final toolResults = response.messages
              .expand((msg) => msg.toolResults)
              .toList();
          expect(
            toolResults,
            isNotEmpty,
            reason: 'Provider ${provider.name} did not execute tool',
          );
        },
        requiredCaps: {ProviderCaps.multiToolCalls},

        timeout: const Timeout(Duration(minutes: 2)),
      );
    });
  });
}
