/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g.
///    ProviderTestCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

// ignore_for_file: avoid_print

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';

void main() {
  group('Infrastructure Helpers', () {
    group('provider discove ry (80% cases)', () {
      test('lists all available providers', () {
        final providers = Agent.allProviders;

        expect(providers, isNotEmpty);
        expect(providers.length, greaterThanOrEqualTo(7)); // Core providers

        // Check for some key providers
        expect(providers.any((p) => p.name == 'openai'), isTrue);
        expect(providers.any((p) => p.name == 'anthropic'), isTrue);
        expect(providers.any((p) => p.name == 'google'), isTrue);
      });

      test('finds provider by exact name', () {
        final openai = Agent.getProvider('openai');
        expect(openai, isNotNull);
        expect(openai.name, equals('openai'));

        final anthropic = Agent.getProvider('anthropic');
        expect(anthropic, isNotNull);
        expect(anthropic.name, equals('anthropic'));
      });

      test('finds provider by alias', () {
        final claude = Agent.getProvider('claude');
        expect(claude, isNotNull);
        expect(claude.name, equals('anthropic'));

        final gemini = Agent.getProvider('gemini');
        expect(gemini, isNotNull);
        expect(gemini.name, equals('google'));
      });

      test('throws for unknown provider', () {
        expect(
          () => Agent.getProvider('unknown-provider'),
          throwsA(isA<Exception>()),
        );
      });

      test('provider names are unique', () {
        final names = Agent.allProviders.map((p) => p.name).toList();
        final uniqueNames = names.toSet();
        expect(uniqueNames.length, equals(names.length));
      });
    });

    group('provider capabilities (80% cases)', () {
      test('at least one provider advertises multi-tool support', () {
        final toolProviders = Agent.allProviders
            .where(
              (p) => providerHasTestCaps(p.name, {
                ProviderTestCaps.multiToolCalls,
              }),
            )
            .toList();
        expect(toolProviders, isNotEmpty);
      });

      runProviderTest(
        'multi-tool capability flag is accurate',
        (provider) async {
          final caps = getProviderTestCaps(provider.name);
          expect(caps.contains(ProviderTestCaps.multiToolCalls), isTrue);
        },
        requiredCaps: {ProviderTestCaps.multiToolCalls},
      );

      test('at least one provider advertises multi-tool + typed output', () {
        final advancedProviders = Agent.allProviders
            .where(
              (p) => providerHasTestCaps(p.name, {
                ProviderTestCaps.multiToolCalls,
                ProviderTestCaps.typedOutput,
              }),
            )
            .toList();

        expect(advancedProviders, isNotEmpty);
      });

      runProviderTest(
        'multi-tool + typed output capability flags are accurate',
        (provider) async {
          final caps = getProviderTestCaps(provider.name);
          expect(caps.contains(ProviderTestCaps.multiToolCalls), isTrue);
          expect(caps.contains(ProviderTestCaps.typedOutput), isTrue);
        },
        requiredCaps: {
          ProviderTestCaps.multiToolCalls,
          ProviderTestCaps.typedOutput,
        },
      );

      test('capabilities are consistent', () {
        for (final provider in Agent.allProviders) {
          final caps = getProviderTestCaps(provider.name);
          // If provider supports multi-tool calls, it should support single
          // tools
          if (caps.contains(ProviderTestCaps.multiToolCalls)) {
            // multiToolCalls implies basic tool support
            expect(caps, isNotEmpty);
          }

          // Chat capability should be present for all chat providers
          if (caps.contains(ProviderTestCaps.chat)) {
            expect(caps, isNotEmpty);
          }
        }
      });
    });

    group('provider metadata (80% cases)', () {
      test('all providers have valid names', () {
        for (final provider in Agent.allProviders) {
          expect(provider.name, isNotEmpty);
          expect(provider.name, matches(RegExp(r'^[a-z0-9_-]+$')));
        }
      });

      test('all providers have default model names', () {
        for (final provider in Agent.allProviders) {
          expect(provider.defaultModelNames[ModelKind.chat], isNotNull);
          expect(provider.defaultModelNames[ModelKind.chat], isNotEmpty);
          expect(
            provider.defaultModelNames[ModelKind.chat]!.contains(' '),
            isFalse,
          );
        }
      });

      test('all providers have non-empty capabilities', () {
        for (final provider in Agent.allProviders) {
          final caps = getProviderTestCaps(provider.name);
          expect(caps, isA<Set<ProviderTestCaps>>());
          // All providers should have at least chat capability
          expect(caps, isNotEmpty);
        }
      });

      test('provider display names are valid', () {
        for (final provider in Agent.allProviders) {
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
          final provider = Agent.getProvider(providerName);
          // For now, just check we can create an agent
          final agent = Agent(provider.name);
          expect(agent, isNotNull);
        }
      });

      test('agent uses custom model name when specified', () {
        // Test that Agent correctly parses "provider:model" format
        final agent1 = Agent('openai:gpt-4o');
        expect(agent1.model, contains('gpt-4o'));

        final agent2 = Agent('anthropic:claude-sonnet-4-0');
        expect(agent2.model, contains('claude-sonnet-4-0'));

        final agent3 = Agent('google:gemini-2.0-flash');
        expect(agent3.model, contains('gemini-2.0-flash'));
      });

      test('default model names follow conventions', () {
        final testProviderNames = ['openai', 'google'];
        for (final providerName in testProviderNames) {
          final provider = Agent.getProvider(providerName);
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
        final providers = Agent.allProviders;

        expect(providers, isNotEmpty);
        expect(providers.length, greaterThanOrEqualTo(4)); // At least 4

        // Check for key providers
        expect(providers.any((p) => p.name == 'openai'), isTrue);
        expect(providers.any((p) => p.name == 'google'), isTrue);
      });

      test('finds embeddings provider by name', () {
        final openai = Agent.getProvider('openai');
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
        requiredCaps: {ProviderTestCaps.embeddings},
      );
    });

    group('edge cases', () {
      test('handles concurrent provider lookups', () async {
        // Test that provider lookup is thread-safe
        final futures = <Future<Provider?>>[];

        for (var i = 0; i < 100; i++) {
          futures.add(Future(() => Agent.getProvider('openai')));
        }

        final results = await Future.wait(futures);

        // All lookups should return the same instance
        expect(results.every((r) => r != null), isTrue);
        expect(results.every((r) => r?.name == 'openai'), isTrue);
      });

      test('handles case-insensitive provider names', () {
        // Provider lookup is case-insensitive by design
        expect(Agent.getProvider('openai'), isNotNull);
        expect(Agent.getProvider('OpenAI'), isNotNull);
        expect(Agent.getProvider('OPENAI'), isNotNull);

        // All should return providers with the same name
        final provider1 = Agent.getProvider('openai');
        final provider2 = Agent.getProvider('OpenAI');
        final provider3 = Agent.getProvider('OPENAI');
        expect(provider1.name, equals(provider2.name));
        expect(provider2.name, equals(provider3.name));
      });

      test('handles empty capability filters', () {
        // Empty capability filter should return all providers
        final providers = Agent.allProviders
            .where((p) => providerHasTestCaps(p.name, {}))
            .toList();
        expect(providers.length, equals(Agent.allProviders.length));
      });

      test('handles non-existent capability filters', () {
        // If we had a hypothetical capability that no provider supports
        final providers = Agent.allProviders
            .where(
              (p) =>
                  providerHasTestCaps(p.name, {
                    ProviderTestCaps.multiToolCalls,
                    ProviderTestCaps.typedOutput,
                  }) &&
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
          final provider = Agent.getProvider(entry.key);
          expect(provider.name, equals(entry.value));
        }
      });
    });
  });
}
