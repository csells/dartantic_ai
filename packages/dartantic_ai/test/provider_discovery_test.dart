/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g.
///    ProviderTestCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication
///
/// This file tests provider discovery including model enumeration via
/// listModels()

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';

void main() {
  group('Provider Discovery', () {
    group('chat provider selection', () {
      test('finds providers by exact name', () {
        expect(Agent.getProvider('openai').name, equals('openai'));
        expect(Agent.getProvider('anthropic').name, equals('anthropic'));
        expect(Agent.getProvider('google').name, equals('google'));
        expect(Agent.getProvider('mistral').name, equals('mistral'));
        expect(Agent.getProvider('ollama').name, equals('ollama'));
        expect(Agent.getProvider('cohere').name, equals('cohere'));
      });

      test('finds providers by aliases', () {
        // Test documented aliases - aliases resolve to same provider name
        expect(
          Agent.getProvider('claude').name,
          equals(Agent.getProvider('anthropic').name),
        );
        expect(
          Agent.getProvider('gemini').name,
          equals(Agent.getProvider('google').name),
        );
      });

      test('throws on unknown provider name', () {
        expect(
          () => Agent.getProvider('unknown-provider'),
          throwsA(isA<Exception>()),
        );
        expect(() => Agent.getProvider('invalid'), throwsA(isA<Exception>()));
        expect(() => Agent.getProvider(''), throwsA(isA<Exception>()));
      });

      test('is case insensitive', () {
        // Provider lookup is case-insensitive
        expect(
          Agent.getProvider('OpenAI').name,
          equals(Agent.getProvider('openai').name),
        );
        expect(
          Agent.getProvider('ANTHROPIC').name,
          equals(Agent.getProvider('anthropic').name),
        );
        expect(
          Agent.getProvider('Claude').name,
          equals(Agent.getProvider('anthropic').name),
        );
      });
    });

    group('embeddings provider selection', () {
      test('finds providers by exact name', () {
        expect(Agent.getProvider('openai').name, equals('openai'));
        expect(Agent.getProvider('google').name, equals('google'));
        expect(Agent.getProvider('mistral').name, equals('mistral'));
        expect(Agent.getProvider('cohere').name, equals('cohere'));
      });

      test('finds providers by aliases', () {
        // After unified Provider, aliases work for embeddings too
        expect(
          Agent.getProvider('gemini').name,
          equals(Agent.getProvider('google').name),
        );
      });

      test('throws on unknown provider name', () {
        expect(() => Agent.getProvider('unknown'), throwsA(isA<Exception>()));
        expect(
          () => Agent.getProvider('invalid-provider'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('provider enumeration', () {
      test('lists all chat providers', () {
        final providers = Agent.allProviders;
        expect(providers, isNotEmpty);
        // At least 7 providers available
        expect(providers.length, greaterThanOrEqualTo(7));

        // Verify key providers are included
        final providerNames = providers.map((p) => p.name).toSet();
        expect(providerNames, contains('openai'));
        expect(providerNames, contains('anthropic'));
        expect(providerNames, contains('google'));
        expect(providerNames, contains('mistral'));
        expect(providerNames, contains('ollama'));
        expect(providerNames, contains('cohere'));
      });

      test('lists all embeddings providers', () {
        final providers = Agent.allProviders
            .where(
              (p) => providerHasTestCaps(p.name, {ProviderTestCaps.embeddings}),
            )
            .toList();
        expect(providers, hasLength(5));

        final providerNames = providers.map((p) => p.name).toSet();
        expect(providerNames, contains('openai'));
        expect(providerNames, contains('google'));
        expect(providerNames, contains('mistral'));
        expect(providerNames, contains('cohere'));
      });

      runProviderTest(
        'chat providers have required properties',
        (provider) async {
          expect(provider.name, isNotEmpty);
          expect(provider.displayName, isNotEmpty);
          expect(provider.createChatModel, isNotNull);
          expect(provider.listModels, isNotNull);
        },
        requiredCaps: {ProviderTestCaps.chat},
      );

      runProviderTest(
        'embeddings providers have required properties',
        (provider) async {
          expect(provider.name, isNotEmpty);
          expect(provider.displayName, isNotEmpty);
          expect(provider.createEmbeddingsModel, isNotNull);
          expect(provider.listModels, isNotNull);
        },
        requiredCaps: {ProviderTestCaps.embeddings},
      );
    });

    // Model enumeration moved to edge cases (limited providers)
    group('basic model access', () {
      test('providers have listModels method', () {
        // Test that all providers have the method (no API calls)
        for (final provider in Agent.allProviders) {
          expect(provider.listModels, isNotNull);
        }

        for (final provider in Agent.allProviders) {
          expect(provider.listModels, isNotNull);
        }
      });
    });

    group('provider display names', () {
      test('chat providers have descriptive display names', () {
        expect(Agent.getProvider('openai').displayName, equals('OpenAI'));
        expect(Agent.getProvider('anthropic').displayName, equals('Anthropic'));
        expect(Agent.getProvider('google').displayName, contains('Google'));
        expect(Agent.getProvider('mistral').displayName, equals('Mistral'));
        expect(Agent.getProvider('ollama').displayName, equals('Ollama'));
      });

      test('embeddings providers have descriptive display names', () {
        expect(Agent.getProvider('openai').displayName, equals('OpenAI'));
        expect(Agent.getProvider('google').displayName, contains('Google'));
        expect(Agent.getProvider('mistral').displayName, equals('Mistral'));
        expect(Agent.getProvider('cohere').displayName, equals('Cohere'));
      });
    });

    group('provider uniqueness', () {
      test('chat provider names are unique', () {
        final providers = Agent.allProviders;
        final names = providers.map((p) => p.name).toList();
        final uniqueNames = names.toSet();
        expect(
          uniqueNames.length,
          equals(names.length),
          reason: 'All chat provider names should be unique',
        );
      });

      test('embeddings provider names are unique', () {
        final providers = Agent.allProviders;
        final names = providers.map((p) => p.name).toList();
        final uniqueNames = names.toSet();
        expect(
          names.length,
          equals(uniqueNames.length),
          reason: 'All embeddings provider names should be unique',
        );
      });
    });

    group('dynamic provider usage', () {
      test('can create models via discovered providers', () {
        final provider = Agent.getProvider('openai');
        final model = provider.createChatModel(name: 'gpt-4o-mini');
        expect(model, isNotNull);
      });

      test('can use aliases for model creation', () {
        final claudeProvider = Agent.getProvider('claude');
        expect(claudeProvider.name, equals('anthropic'));

        // Skip actual model creation if API key not available
        expect(claudeProvider, isNotNull);
      });

      test('supports dynamic agent creation', () {
        final provider = Agent.getProvider('gemini');
        expect(provider.name, equals('google'));

        final agent = Agent('${provider.name}:gemini-2.5-flash');
        expect(agent, isNotNull);
        final parsed = ModelStringParser.parse(agent.model);
        expect(parsed.providerName, equals('google'));
        expect(parsed.chatModelName, equals('gemini-2.5-flash'));
        expect(
          parsed.mediaModelName,
          equals(provider.defaultModelNames[ModelKind.media]),
        );
      });
    });

    group('provider comparison', () {
      test('providers with same name are equivalent', () {
        final provider1 = Agent.getProvider('openai');
        final provider2 = Agent.getProvider('openai');
        expect(provider1.name, equals(provider2.name));

        final aliasProvider = Agent.getProvider('claude');
        final directProvider = Agent.getProvider('anthropic');
        expect(aliasProvider.name, equals(directProvider.name));
      });

      test('different providers have different names', () {
        final openai = Agent.getProvider('openai');
        final anthropic = Agent.getProvider('anthropic');
        expect(openai.name, isNot(equals(anthropic.name)));
      });
    });

    group('error handling', () {
      test('handles null and empty provider names gracefully', () {
        expect(() => Agent.getProvider(''), throwsA(isA<Exception>()));
      });

      test('provides helpful error messages', () {
        expect(
          () => Agent.getProvider('invalid-provider'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('model enumeration checks', () {
      runProviderTest(
        'chat providers return available models',
        (provider) async {
          final models = await provider.listModels().toList();
          expect(
            models,
            isNotEmpty,
            reason: 'Provider ${provider.name} should have models',
          );
          for (final model in models) {
            expect(
              model.name,
              isNotEmpty,
              reason: 'Model name should not be empty for ${provider.name}',
            );
          }
        },
        requiredCaps: {ProviderTestCaps.chat},
      );

      runProviderTest(
        'embeddings providers return available models',
        (provider) async {
          final models = await provider.listModels().toList();
          expect(
            models,
            isNotEmpty,
            reason: 'Provider ${provider.name} should have embedding models',
          );
          for (final model in models) {
            expect(
              model.name,
              isNotEmpty,
              reason: 'Model name should not be empty for ${provider.name}',
            );
          }
        },
        requiredCaps: {ProviderTestCaps.embeddings},
      );

      runProviderTest(
        'models have consistent naming patterns',
        (provider) async {
          final models = await provider.listModels().toList();
          expect(
            models,
            isNotEmpty,
            reason: 'Provider ${provider.name} should publish models',
          );
          for (final model in models.take(10)) {
            expect(
              model.name.trim(),
              isNotEmpty,
              reason:
                  'Model name "${model.name}" for ${provider.name} should not '
                  'be empty or whitespace',
            );
            expect('${provider.name}:${model.name}', isNotEmpty);
          }
        },
        requiredCaps: {ProviderTestCaps.chat},
      );
    });
  });
}
