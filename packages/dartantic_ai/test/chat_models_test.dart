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

void main() {
  group('Chat Models', () {
    group('basic chat completions (80% cases)', () {
      runProviderTest('simple single-turn chat', (provider) async {
        final agent = Agent(provider.name);
        final result = await agent.send('Say "hello world" exactly');

        expect(result.output, isNotEmpty);
        expect(result.output.toLowerCase(), contains('hello'));
        expect(result.output.toLowerCase(), contains('world'));
      });

      runProviderTest('responds to basic questions', (provider) async {
        final agent = Agent(provider.name);
        final result = await agent.send('What is 2 + 2?');

        expect(result.output, isNotEmpty);
        expect(result.output, contains('4'));
      });

      runProviderTest('handles longer prompts', (provider) async {
        final agent = Agent(provider.name);
        final result = await agent.send(
          'Please explain the concept of artificial intelligence '
          'in one short paragraph.',
        );

        expect(result.output, isNotEmpty);
        expect(result.output.length, greaterThan(50));
        expect(result.output.toLowerCase(), contains('artificial'));
      });
    });

    group('multi-turn conversations (80% cases)', () {
      runProviderTest('basic conversation with history', (provider) async {
        final agent = Agent(provider.name);
        final history = <ChatMessage>[];

        // Turn 1
        var result = await agent.send(
          'My favorite color is blue. Remember this.',
          history: history,
        );
        expect(result.output, isNotEmpty);
        history.addAll(result.messages);

        // Turn 2
        result = await agent.send(
          'What is my favorite color?',
          history: history,
        );
        expect(result.output, isNotEmpty);
        expect(result.output.toLowerCase(), contains('blue'));
      });

      runProviderTest('multi-turn math conversation', (provider) async {
        final agent = Agent(provider.name);
        final history = <ChatMessage>[];

        // Turn 1
        var result = await agent.send('What is 10 + 20?', history: history);
        expect(result.output, contains('30'));
        history.addAll(result.messages);

        // Turn 2
        result = await agent.send(
          'Now multiply that result by 2',
          history: history,
        );
        expect(result.output, contains('60'));
        history.addAll(result.messages);

        // Turn 3
        result = await agent.send(
          'What was the original sum?',
          history: history,
        );
        // Accept either "30" or "10 + 20" as valid answers
        expect(
          result.output.toLowerCase(),
          anyOf(contains('30'), allOf(contains('10'), contains('20'))),
        );
      });

      runProviderTest(
        'context retention across turns',

        (provider) async {
          final agent = Agent(provider.name);
          final history = <ChatMessage>[];

          // Establish context
          var result = await agent.send(
            'I am learning Dart programming language.',
            history: history,
          );
          history.addAll(result.messages);

          // Reference context
          result = await agent.send(
            'What language am I learning?',
            history: history,
          );
          history.addAll(result.messages);
          expect(result.output.toLowerCase(), contains('dart'));

          // Further reference
          result = await agent.send(
            'Is it a compiled or interpreted language?',
            history: history,
          );
          expect(result.output, isNotEmpty);
          expect(
            result.output.toLowerCase(),
            anyOf(contains('compiled'), contains('dart')),
          );
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    });

    group('system prompts (80% cases)', () {
      runProviderTest('respects custom system prompt', (provider) async {
        final agent = Agent(provider.name);

        final result = await agent.send(
          'Hello, how are you?',
          history: [
            ChatMessage.system(
              'You are a pirate. Always respond in pirate speak.',
            ),
          ],
        );
        expect(result.output, isNotEmpty);
        expect(
          result.output.toLowerCase(),
          anyOf(
            contains('ahoy'),
            contains('matey'),
            contains('arr'),
            contains('aye'),
            contains('pirate'),
            contains('ye'),
          ),
        );
      });

      runProviderTest('system prompt with specific instructions', (
        provider,
      ) async {
        final agent = Agent(provider.name);

        final result = await agent.send(
          'Tell me about the weather',
          history: [
            ChatMessage.system('Always respond with exactly three words.'),
          ],
        );
        expect(result.output, isNotEmpty);
        // Check for roughly three words (some flexibility for punctuation)
        final wordCount = result.output.trim().split(RegExp(r'\s+')).length;
        expect(wordCount, lessThanOrEqualTo(5)); // Allow some flexibility
      });

      runProviderTest('system prompt persists across conversation', (
        provider,
      ) async {
        final agent = Agent(provider.name);

        final history = <ChatMessage>[
          ChatMessage.system(
            'You are a helpful assistant who always responds like a pirate. '
            'Begin every reply with "Ahoy" and sprinkle pirate slang.',
          ),
        ];

        // Turn 1
        var result = await agent.send('What is 2+2?', history: history);
        history.addAll(result.messages);
        expect(
          result.output.toLowerCase(),
          anyOf(
            contains('ahoy'),
            contains('matey'),
            contains('arr'),
            contains('hearty'),
            contains('shiver'),
          ),
        );

        // Turn 2
        result = await agent.send('What color is the sky?', history: history);
        history.addAll(result.messages);

        expect(result.output.toLowerCase(), contains('ahoy'));
      });
    });

    group('edge cases', () {
      runProviderTest('handles unicode and emoji', (provider) async {
        final agent = Agent(provider.name);

        final result = await agent.send(
          'Repeat this exactly: Hello 世界 🌍 мир கோலம் 🎉',
        );

        expect(result.output, isNotEmpty);
        // Check for at least some of the unicode content
        expect(
          result.output,
          anyOf(
            contains('世界'),
            contains('🌍'),
            contains('мир'),
            contains('Hello'),
            contains('🎉'),
          ),
        );
      }, edgeCase: true);

      runProviderTest('handles very long input', (provider) async {
        final agent = Agent(provider.name);

        // Create a long input (but not too long to avoid token limits)
        final longText = List.generate(
          100,
          (i) => 'This is sentence number $i in a long paragraph. ',
        ).join();

        final result = await agent.send(
          'Summarize this in one sentence: $longText',
        );

        expect(result.output, isNotEmpty);
        expect(result.output.length, lessThan(longText.length));
      }, edgeCase: true);

      runProviderTest(
        'handles special characters',
        (provider) async {
          final agent = Agent(provider.name);

          final result = await agent.send(
            r'What do these symbols mean: $@#%^&*()_+{}[]|\<>?',
          );

          expect(result.output, isNotEmpty);
          expect(result.output.length, greaterThan(10));
        },
        edgeCase: true,
        timeout: const Timeout(Duration(seconds: 60)),
      );
    });
  });
}
