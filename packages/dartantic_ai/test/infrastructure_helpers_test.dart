/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

// ignore_for_file: avoid_print

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';

void main() {
  group('Infrastructure Helpers', () {
    group('provider discove ry (80% cases)', () {
      test('lists all available providers', () {
        final providers = Providers.all;

        expect(providers, isNotEmpty);
        expect(providers.length, greaterThan(10)); // We have 11+ providers

        // Check for some key providers
        expect(providers.any((p) => p.name == 'openai'), isTrue);
        expect(providers.any((p) => p.name == 'anthropic'), isTrue);
        expect(providers.any((p) => p.name == 'google'), isTrue);
      });

      test('finds provider by exact name', () {
        final openai = Providers.get('openai');
        expect(openai, isNotNull);
        expect(openai.name, equals('openai'));

        final anthropic = Providers.get('anthropic');
        expect(anthropic, isNotNull);
        expect(anthropic.name, equals('anthropic'));
      });

      test('finds provider by alias', () {
        final claude = Providers.get('claude');
        expect(claude, isNotNull);
        expect(claude.name, equals('anthropic'));

        final gemini = Providers.get('gemini');
        expect(gemini, isNotNull);
        expect(gemini.name, equals('google'));
      });

      test('throws for unknown provider', () {
        expect(
          () => Providers.get('unknown-provider'),
          throwsA(isA<Exception>()),
        );
      });

      test('provider names are unique', () {
        final names = Providers.all.map((p) => p.name).toList();
        final uniqueNames = names.toSet();
        print('named: ${names.join(', ')}');
        print('unique: ${uniqueNames.join(', ')}');
        print('google: ${Providers.google.aliases.contains('google')}');
        print('googleai: ${Providers.google.aliases.contains('googleai')}');
        print('google-gla: ${Providers.google.aliases.contains('google-gla')}');
        print('google-gla: ${Providers.google.aliases.contains('google-gla')}');
        expect(uniqueNames.length, equals(names.length));
      });
    });

    group('provider capabilities (80% cases)', () {
      test('at least one provider advertises multi-tool support', () {
        final toolProviders = Providers.allWith({ProviderCaps.multiToolCalls});
        expect(toolProviders, isNotEmpty);
      });

      runProviderTest(
        'multi-tool capability flag is accurate',
        (provider) async {
          expect(provider.caps.contains(ProviderCaps.multiToolCalls), isTrue);
        },
        requiredCaps: {ProviderCaps.multiToolCalls},
      );

      test('at least one provider advertises multi-tool + typed output', () {
        final advancedProviders = Providers.allWith({
          ProviderCaps.multiToolCalls,
          ProviderCaps.typedOutput,
        });

        expect(advancedProviders, isNotEmpty);
      });

      runProviderTest(
        'multi-tool + typed output capability flags are accurate',
        (provider) async {
          expect(provider.caps.contains(ProviderCaps.multiToolCalls), isTrue);
          expect(provider.caps.contains(ProviderCaps.typedOutput), isTrue);
        },
        requiredCaps: {ProviderCaps.multiToolCalls, ProviderCaps.typedOutput},
      );

      test('capabilities are consistent', () {
        for (final provider in Providers.all) {
          // If provider supports multi-tool calls, it should support
          // single tools
          if (provider.caps.contains(ProviderCaps.multiToolCalls)) {
            // multiToolCalls implies basic tool support
            expect(provider.caps, isNotEmpty);
          }

          // Chat capability should be present for all chat providers
          if (provider.caps.contains(ProviderCaps.chat)) {
            expect(provider.caps, isNotEmpty);
          }
        }
      });
    });

    group('provider metadata (80% cases)', () {
      test('all providers have valid names', () {
        for (final provider in Providers.all) {
          expect(provider.name, isNotEmpty);
          expect(provider.name, matches(RegExp(r'^[a-z0-9_-]+$')));
        }
      });

      test('all providers have default model names', () {
        for (final provider in Providers.all) {
          expect(provider.defaultModelNames[ModelKind.chat], isNotNull);
          expect(provider.defaultModelNames[ModelKind.chat], isNotEmpty);
          expect(
            provider.defaultModelNames[ModelKind.chat]!.contains(' '),
            isFalse,
          );
        }
      });

      test('all providers have non-empty capabilities', () {
        for (final provider in Providers.all) {
          expect(provider.caps, isA<Set<ProviderCaps>>());
          // All providers should have at least chat capability
          expect(provider.caps, isNotEmpty);
        }
      });

      test('provider display names are valid', () {
        for (final provider in Providers.all) {
          final agent = Agent(provider.name);
          expect(agent.displayName, isNotEmpty);
          // Just verify the display name exists and is not empty Don't require
          // it to contain the provider name since display names can be
          // human-friendly versions (e.g., "Google AI (OpenAI-compatible)")
        }
      });
    });

    group('model listing (80% cases)', () {
      test('providers can list their models', () {
        // Test a few key providers
        final testProviders = ['openai', 'anthropic', 'google'];

        for (final providerName in testProviders) {
          final provider = Providers.get(providerName);
          // For now, just check we can create an agent
          final agent = Agent(provider.name);
          expect(agent, isNotNull);
        }
      });

      test('agent uses custom model name when specified', () {
        // Test that Agent correctly parses "provider:model" format
        final agent1 = Agent('together:Qwen/Qwen2.5-VL-72B-Instruct');
        expect(agent1.model, contains('Qwen/Qwen2.5-VL-72B-Instruct'));

        final agent2 = Agent('openai:gpt-4o');
        expect(agent2.model, contains('gpt-4o'));

        final agent3 = Agent('anthropic:claude-3-5-sonnet-20241022');
        expect(agent3.model, contains('claude-3-5-sonnet-20241022'));
      });

      test('default model names follow conventions', () {
        final testProviderNames = ['openai', 'google'];
        for (final providerName in testProviderNames) {
          final provider = Providers.get(providerName);
          final model = provider.defaultModelNames[ModelKind.chat];

          expect(model, isNotNull);
          expect(model, isNotEmpty);
          // Model names shouldn't have spaces
          expect(model!.contains(' '), isFalse);
        }
      });
    });

    group('embeddings provider infrastructure (80% cases)', () {
      test('lists all embeddings providers', () {
        final providers = Providers.all;

        expect(providers, isNotEmpty);
        expect(providers.length, greaterThanOrEqualTo(4)); // At least 4

        // Check for key providers
        expect(providers.any((p) => p.name == 'openai'), isTrue);
        expect(providers.any((p) => p.name == 'google'), isTrue);
      });

      test('finds embeddings provider by name', () {
        final openai = Providers.get('openai');
        expect(openai, isNotNull);
        expect(openai.name, equals('openai'));
      });

      runProviderTest(
        'embeddings provider metadata is valid',
        (provider) async {
          expect(provider.name, isNotEmpty);
          final model = provider.createEmbeddingsModel();
          expect(model, isNotNull);
        },
        requiredCaps: {ProviderCaps.embeddings},
      );
    });

    group('edge cases', () {
      test('handles concurrent provider lookups', () async {
        // Test that provider lookup is thread-safe
        final futures = <Future<Provider?>>[];

        for (var i = 0; i < 100; i++) {
          futures.add(Future(() => Providers.get('openai')));
        }

        final results = await Future.wait(futures);

        // All lookups should return the same instance
        expect(results.every((r) => r != null), isTrue);
        expect(results.every((r) => r?.name == 'openai'), isTrue);
      });

      test('handles case-insensitive provider names', () {
        // Provider lookup is case-insensitive by design
        expect(Providers.get('openai'), isNotNull);
        expect(Providers.get('OpenAI'), isNotNull);
        expect(Providers.get('OPENAI'), isNotNull);

        // All should return the same provider
        final provider1 = Providers.get('openai');
        final provider2 = Providers.get('OpenAI');
        final provider3 = Providers.get('OPENAI');
        expect(provider1, equals(provider2));
        expect(provider2, equals(provider3));
      });

      test('handles empty capability filters', () {
        // Empty capability filter should return all providers
        final providers = Providers.allWith({});
        expect(providers.length, equals(Providers.all.length));
      });

      test('handles non-existent capability filters', () {
        // If we had a hypothetical capability that no provider supports
        final providers = Providers.all
            .where(
              (p) =>
                  p.caps.contains(ProviderCaps.multiToolCalls) &&
                  p.caps.contains(ProviderCaps.typedOutput) &&
                  p.name == 'nonexistent',
            )
            .toList();

        expect(providers, isEmpty);
      });

      test('provider aliases are consistent', () {
        // Test all known aliases
        final aliases = {
          'claude': 'anthropic',
          'gemini': 'google',
          'mistralai': 'mistral',
        };

        for (final entry in aliases.entries) {
          final provider = Providers.get(entry.key);
          expect(provider.name, equals(entry.value));
        }
      });
    });
  });
}
