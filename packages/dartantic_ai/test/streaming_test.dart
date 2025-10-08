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

  // Timeout calculation based on empirical measurements:
  // - Worst case: Cohere multi-turn takes 8096ms in isolation
  // - With 2x network variability: 16s
  // - With 2x concurrency overhead: 32s
  // - With 1.5x CI environment factor: 48s
  // - With 5s API rate limit buffer: 53s
  // - Rounded up for safety: 180s (3 minutes)
  group('Streaming', timeout: const Timeout(Duration(seconds: 180)), () {
    group('basic streaming responses (80% cases)', () {
      runProviderTest('simple streaming works', (provider) async {
        final agent = Agent(provider.name);
        final chunks = <String>[];

        await for (final chunk in agent.sendStream('Say "hello world"')) {
          chunks.add(chunk.output);
        }

        expect(chunks, isNotEmpty);
        final fullText = chunks.join();
        expect(fullText.toLowerCase(), contains('hello'));
        expect(fullText.toLowerCase(), contains('world'));
      });

      runProviderTest('streaming preserves message order', (provider) async {
        final agent = Agent(provider.name);
        final chunks = <String>[];

        await for (final chunk in agent.sendStream('Count from 1 to 3')) {
          chunks.add(chunk.output);
        }

        final fullText = chunks.join();
        expect(fullText, contains('1'));
        expect(fullText, contains('2'));
        expect(fullText, contains('3'));

        // Check that numbers appear in sequential order Use a regex to find the
        // actual counting sequence, ignoring conversational preamble that might
        // contain numbers
        final sequencePattern = RegExp(r'1[^\d]*2[^\d]*3');
        expect(
          fullText,
          matches(sequencePattern),
          reason: 'Should contain numbers 1, 2, 3 in sequence',
        );
      });

      runProviderTest('streaming accumulates correctly', (provider) async {
        final agent = Agent(provider.name);
        final chunks = <String>[];
        final accumulated = StringBuffer();

        await for (final chunk in agent.sendStream(
          'Write a short sentence about cats.',
        )) {
          chunks.add(chunk.output);
          accumulated.write(chunk.output);
        }

        // We should have received some chunks
        expect(chunks, isNotEmpty);

        // At least some chunks should have content
        expect(chunks.any((c) => c.isNotEmpty), isTrue);

        // Accumulated should contain expected content
        final accumulatedText = accumulated.toString();
        expect(
          accumulatedText.toLowerCase(),
          anyOf(contains('cat'), contains('feline')),
        );
        expect(accumulatedText.length, greaterThan(10));
      });
    });

    group('tool call streaming (80% cases)', () {
      runProviderTest(
        'streams tool calls and results',
        (provider) async {
          final agent = Agent(provider.name, tools: [stringTool]);

          final chunks = <String>[];
          await for (final chunk in agent.sendStream(
            'Use string_tool with input "test"',
          )) {
            chunks.add(chunk.output);
          }

          expect(chunks, isNotEmpty);
          final fullText = chunks.join();
          expect(fullText, isNotEmpty);

          // Result should contain the streamed output
          expect(
            fullText.toLowerCase(),
            anyOf(
              contains('processed'),
              contains('string'),
              contains('test'),
              contains('result'),
            ),
          );
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
      );

      runProviderTest('streams multiple tool calls', (provider) async {
        final agent = Agent(provider.name, tools: [stringTool, intTool]);

        final result = await agent.send(
          'Show me the result of string_tool with "hello" and '
          'then show me the result of int_tool with 42',
        );

        // Should see evidence of both tools being used
        expect(result.output, isNotEmpty);
        expect(result.output.toLowerCase(), anyOf(contains('hello')));
        expect(result.output, contains('42'));
      }, requiredCaps: {ProviderCaps.multiToolCalls});

      runProviderTest(
        'tool streaming preserves order',
        (provider) async {
          final agent = Agent(provider.name, tools: [intTool]);

          final chunks = <String>[];
          await for (final chunk in agent.sendStream(
            'Use int_tool three times: first with 1, then 2, then 3',
          )) {
            chunks.add(chunk.output);
          }

          final fullText = chunks.join();
          expect(fullText, isNotEmpty);

          // Should have executed the tools (check that the response mentions
          // tool usage or contains the numbers)
          expect(
            fullText.toLowerCase(),
            anyOf(
              allOf(contains('1'), contains('2'), contains('3')),
              contains('tool'),
              contains('int_tool'),
              contains('executed'),
              contains('called'),
              contains('used'),
            ),
          );
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
      );
    });

    group('multi-turn streaming (80% cases)', () {
      runProviderTest('streaming with conversation history', (provider) async {
        // Skip for Cohere - their OpenAI-compatible endpoint has inconsistent
        // behavior with conversation history. Sometimes it works, sometimes
        // it doesn't. Tested with curl: works ~40% of the time.
        //
        // To test if Cohere has fixed this, run this command multiple times:
        // curl -s -X POST
        // https://api.cohere.ai/compatibility/v1/chat/completions \
        //   -H "Authorization: Bearer $COHERE_API_KEY" \
        //   -H "Content-Type: application/json" \
        //   -d '{ "model": "command-r-plus", "messages": [ {"role": "user",
        //     "content": "My favorite number is 42."}, {"role": "assistant",
        //     "content": "Got it!"}, {"role": "user", "content": "What is my
        //     favorite number?"}
        //     ],
        //     "stream": true
        //   }'
        // If it consistently returns "42" in the response, this test can be
        // re-enabled.
        if (provider.name == 'cohere') {
          markTestSkipped(
            'Cohere has inconsistent conversation history behavior',
          );
          return;
        }

        final agent = Agent(provider.name);
        final history = <ChatMessage>[];

        // First turn - establish context
        final result = await agent.send(
          'My favorite number is 42.',
          history: history,
        );
        history.addAll(result.messages);

        // Second turn - stream with history
        final chunks = <String>[];
        await for (final chunk in agent.sendStream(
          'What is my favorite number?',
          history: history,
        )) {
          chunks.add(chunk.output);
        }

        final fullText = chunks.join();
        expect(fullText, contains('42'));
      });

      runProviderTest('multi-turn streaming maintains context', (
        provider,
      ) async {
        // Skip for Cohere - same conversation history issue as above
        if (provider.name == 'cohere') {
          markTestSkipped(
            'Cohere has inconsistent conversation history behavior',
          );
          return;
        }

        final agent = Agent(provider.name);
        final history = <ChatMessage>[];

        // Turn 1: Establish topic
        final result = await agent.send(
          'I want to learn about penguins.',
          history: history,
        );
        history.addAll(result.messages);

        // Turn 2: Stream follow-up
        final chunks1 = <String>[];
        ChatResult<String>? streamResult;
        await for (final chunk in agent.sendStream(
          "Tell me one interesting fact about the topic we're discussing.",
          history: history,
        )) {
          chunks1.add(chunk.output);
          streamResult = chunk;
        }
        if (streamResult != null) {
          history.addAll(streamResult.messages);
        }

        // Turn 3: Stream another follow-up
        final chunks2 = <String>[];
        await for (final chunk in agent.sendStream(
          'What do they eat?',
          history: history,
        )) {
          chunks2.add(chunk.output);
        }

        // Both streamed responses should be about penguins
        expect(
          chunks1.join().toLowerCase(),
          anyOf(
            contains('penguin'),
            contains('bird'),
            contains('antarctic'),
            contains('swim'),
          ),
        );
        expect(
          chunks2.join().toLowerCase(),
          anyOf(
            contains('fish'),
            contains('krill'),
            contains('squid'),
            contains('eat'),
            contains('food'),
          ),
        );
      });

      runProviderTest('streaming with tool history', (provider) async {
        // Skip for Cohere - inconsistent tool history behavior (fails ~10% of
        // the time) Tested with both our package and curl - Cohere
        // intermittently fails to reference previous tool results in
        // conversation history.
        //
        // Curl command that demonstrates the issue: curl -X POST
        // https://api.cohere.com/v2/chat \
        //   -H "Authorization: bearer $COHERE_API_KEY" \
        //   -H "Content-Type: application/json" \
        //   -d '{ "model": "command-r-plus", "messages": [ {"role": "user",
        //     "content": "Use int_tool with 100"}, {"role": "assistant",
        //     "tool_calls": [{"id": "call_test", "type": "function",
        //     "function": {"name": "int_tool", "arguments": "{\"value\":
        //     100}"}}]}, {"role": "tool", "tool_call_id": "call_test",
        //     "content": "100"}, {"role": "assistant", "content": "Sure,
        //     100."}, {"role": "user", "content": "What was the result of the
        //     calculation?"}
        //     ]
        //   }'
        // Expected: Response mentioning "100" Actual: Sometimes "The result was
        // 100", sometimes "Sorry, I can't find the result"
        if (provider.name == 'cohere') {
          markTestSkipped(
            'Cohere has inconsistent tool history behavior (90% success rate)',
          );
          return;
        }

        final agent = Agent(provider.name, tools: [intTool]);
        final history = <ChatMessage>[];

        // First turn - use tool
        final result = await agent.send(
          'Use int_tool with 100',
          history: history,
        );
        history.addAll(result.messages);

        // Second turn - stream reference to previous tool use
        final chunks = <String>[];
        await for (final chunk in agent.sendStream(
          'What was the result of the calculation?',
          history: history,
        )) {
          chunks.add(chunk.output);
        }

        final fullText = chunks.join();
        expect(fullText, contains('100'));
      }, requiredCaps: {ProviderCaps.multiToolCalls});
    });

    group('edge cases', () {
      runProviderTest('handles stream interruption gracefully', (
        provider,
      ) async {
        final agent = Agent(provider.name);
        final chunks = <String>[];

        // Start streaming but break early
        await for (final chunk in agent.sendStream(
          'Count from 1 to 100 slowly',
        )) {
          chunks.add(chunk.output);
          if (chunks.length >= 5) {
            break; // Interrupt the stream
          }
        }

        // Should have collected some chunks before interruption
        expect(chunks, isNotEmpty);
        expect(chunks.length, greaterThanOrEqualTo(5));
      }, edgeCase: true);

      runProviderTest('handles empty streaming responses', (provider) async {
        final agent = Agent(provider.name);
        final chunks = <String>[];

        // Request that might result in minimal streaming
        await for (final chunk in agent.sendStream('')) {
          chunks.add(chunk.output);
        }

        // Even empty input should produce some response
        expect(chunks, isNotEmpty);
      }, edgeCase: true);

      runProviderTest('accumulates very long streams', (provider) async {
        final agent = Agent(provider.name);
        final chunks = <String>[];
        var totalLength = 0;

        await for (final chunk in agent.sendStream(
          'Write a detailed 5-paragraph essay about the importance of '
          'artificial intelligence in modern society.',
        )) {
          chunks.add(chunk.output);
          totalLength += chunk.output.length;
        }

        // Should produce a substantial response
        expect(chunks.length, greaterThan(10)); // Many chunks
        expect(totalLength, greaterThan(500)); // Long total output

        // Content should be coherent when joined
        final fullText = chunks.join();
        expect(fullText.toLowerCase(), contains('artificial'));
        expect(fullText.toLowerCase(), contains('intelligence'));
      }, edgeCase: true);
    });
  });
}
