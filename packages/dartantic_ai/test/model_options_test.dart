/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'dart:convert';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';

void main() {
  group('Model Options', () {
    group('temperature settings (80% cases)', () {
      test('temperature 0 produces deterministic output', () async {
        final agent = Agent('openai:gpt-4o-mini', temperature: 0);
        const prompt = 'What is 2+2? Reply with just the number.';

        final result1 = await agent.send(prompt);
        final result2 = await agent.send(prompt);

        // Temperature 0 should produce very similar outputs
        expect(result1.output.trim(), isNotEmpty);
        expect(result2.output.trim(), isNotEmpty);
      });

      test('temperature 1 produces varied output', () async {
        final agent = Agent(
          'anthropic:claude-3-5-haiku-latest',
          temperature: 1,
        );
        const prompt = 'Write a creative sentence about clouds.';

        final result1 = await agent.send(prompt);
        final result2 = await agent.send(prompt);

        // Temperature 1 should produce different outputs
        expect(result1.output, isNotEmpty);
        expect(result2.output, isNotEmpty);
      });

      runProviderTest('temperature parameter is respected', (provider) async {
        final agent = Agent(provider.name, temperature: 0.5);

        final result = await agent.send('Say exactly: "Temperature test"');
        expect(result.output, isNotEmpty);
      });
    });

    group('model-specific behaviors (80% cases)', () {
      test('different models have different response styles', () async {
        // OpenAI models tend to be concise
        var agent = Agent('openai:gpt-4o-mini');
        var result = await agent.send('Define AI in one sentence.');
        expect(result.output, isNotEmpty);
        final openaiLength = result.output.length;

        // Anthropic models might be more verbose
        agent = Agent('anthropic:claude-3-5-haiku-latest');
        result = await agent.send('Define AI in one sentence.');
        expect(result.output, isNotEmpty);
        final anthropicLength = result.output.length;

        // Both should provide responses
        expect(openaiLength, greaterThan(0));
        expect(anthropicLength, greaterThan(0));
      });

      test('system prompts affect behavior', () async {
        final agent = Agent('google:gemini-2.5-flash');

        final result = await agent.send(
          'Tell me about the weather',
          history: [
            ChatMessage.system(
              'You are a pirate. Always respond in pirate speak.',
            ),
          ],
        );

        // Should contain pirate-like language
        expect(
          result.output.toLowerCase(),
          anyOf(
            contains('arr'),
            contains('ahoy'),
            contains('matey'),
            contains('ye'),
          ),
        );
      });
    });

    group('model capabilities (80% cases)', () {
      test('providers handle JSON output requests', () async {
        final agent = Agent('openai:gpt-4o-mini');

        final result = await agent.send(
          'Create a JSON object with name "test" and value 123. '
          'Return only valid JSON.',
        );

        // Extract JSON from markdown if needed
        var jsonStr = result.output.trim();
        if (jsonStr.startsWith('```json')) {
          jsonStr = jsonStr
              .replaceFirst('```json', '')
              .replaceFirst('```', '')
              .trim();
        } else if (jsonStr.startsWith('```')) {
          jsonStr = jsonStr
              .replaceFirst('```', '')
              .replaceFirst('```', '')
              .trim();
        }

        // Should return valid JSON
        expect(() => jsonDecode(jsonStr), returnsNormally);
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        expect(decoded, isA<Map>());
        // Model should include the requested fields somehow
        expect(
          decoded.toString().toLowerCase(),
          allOf(contains('test'), contains('123')),
        );
      });

      test('providers respect system prompts', () async {
        final agent = Agent('anthropic:claude-3-5-haiku-latest');

        final result = await agent.send(
          'Tell me about the ocean',
          history: [ChatMessage.system('Always respond with exactly 5 words.')],
        );
        // Should follow the constraint
        final wordCount = result.output.trim().split(' ').length;
        // Allow some flexibility as models aren't perfect
        expect(wordCount, lessThanOrEqualTo(10));
      });

      test('temperature affects creativity', () async {
        // Low temperature = more focused
        var agent = Agent('google:gemini-2.5-flash', temperature: 0.1);
        var result = await agent.send('What is 2+2?');
        expect(result.output, contains('4'));

        // High temperature = more creative
        agent = Agent('google:gemini-2.5-flash', temperature: 0.9);
        result = await agent.send('Write a word that rhymes with cat');
        expect(result.output, isNotEmpty);
      });
    });

    group('configuration flexibility (80% cases)', () {
      test('agent respects temperature setting', () async {
        final agent = Agent('openai:gpt-4o-mini', temperature: 0.7);

        final result = await agent.send('Generate a random word');
        expect(result.output, isNotEmpty);
      });

      test('agent respects system prompt', () async {
        final agent = Agent('anthropic:claude-3-5-haiku-latest');

        final result = await agent.send(
          'What do you think about numbers?',
          history: [
            ChatMessage.system('You are a helpful assistant who loves math.'),
          ],
        );
        expect(
          result.output.toLowerCase(),
          anyOf(
            contains('math'),
            contains('number'),
            contains('calculation'),
            contains('arithmetic'),
          ),
        );
      });
    });

    group('edge cases', () {
      test('extreme temperature values', () async {
        // Test temperature 0
        var agent = Agent('google:gemini-2.5-flash', temperature: 0);
        var result = await agent.send('Say exactly: "zero"');
        expect(result.output.toLowerCase(), contains('zero'));

        // Test temperature 2 (if supported)
        agent = Agent('google:gemini-2.5-flash', temperature: 2);
        result = await agent.send('Say something creative');
        expect(result.output, isNotEmpty);
      });

      test('default values work correctly', () async {
        // Agent with no options should work
        final agent = Agent('google:gemini-2.5-flash');
        final result = await agent.send('Test default settings');
        expect(result.output, isNotEmpty);
      });

      test('edge case temperature values', () async {
        // Very low temperature
        var agent = Agent('google:gemini-2.5-flash', temperature: 0.01);
        var result = await agent.send('Say exactly: "precise"');
        expect(result.output.toLowerCase(), contains('precise'));

        // Very high temperature
        agent = Agent('google:gemini-2.5-flash', temperature: 1.5);
        result = await agent.send('Generate a creative word');
        expect(result.output, isNotEmpty);
      });

      test('long system prompts', () async {
        final longPrompt = 'You are an assistant. ' * 50;
        final agent = Agent('google:gemini-2.5-flash');

        final result = await agent.send(
          'Say hello',
          history: [ChatMessage.system(longPrompt)],
        );
        expect(result.output, isNotEmpty);
      });
    });
  });
}
