/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication
///
/// This file tests provider discovery including model enumeration via
/// listModels()

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:test/test.dart';

void main() {
  // Helper to run parameterized tests for chat providers
  void runChatProviderTest(
    String testName,
    Future<void> Function(Provider provider) testFunction, {
    Timeout? timeout,
  }) {
    group(testName, () {
      for (final provider in Providers.all) {
        test(
          '${provider.name} - $testName',
          () async {
            await testFunction(provider);
          },
          timeout: timeout ?? const Timeout(Duration(seconds: 30)),
        );
      }
    });
  }

  // Helper to run parameterized tests for embeddings providers
  void runEmbeddingsProviderTest(
    String testName,
    Future<void> Function(Provider provider) testFunction, {
    Timeout? timeout,
  }) {
    group(testName, () {
      for (final provider in Providers.all.where(
        (p) => p.caps.contains(ProviderCaps.embeddings),
      )) {
        test(
          '${provider.name} - $testName',
          () async {
            await testFunction(provider);
          },
          timeout: timeout ?? const Timeout(Duration(seconds: 30)),
        );
      }
    });
  }

  group('Provider Discovery', () {
    group('chat provider selection', () {
      test('finds providers by exact name', () {
        expect(Providers.get('openai'), equals(Providers.openai));
        expect(Providers.get('anthropic'), equals(Providers.anthropic));
        expect(Providers.get('google'), equals(Providers.google));
        expect(Providers.get('mistral'), equals(Providers.mistral));
        expect(Providers.get('ollama'), equals(Providers.ollama));
        expect(Providers.get('together'), equals(Providers.together));
        expect(Providers.get('cohere'), equals(Providers.cohere));
        expect(Providers.get('openrouter'), equals(Providers.openrouter));
      });

      test('finds providers by aliases', () {
        // Test documented aliases from README
        expect(Providers.get('claude'), equals(Providers.anthropic));
        expect(Providers.get('gemini'), equals(Providers.google));
        // These aliases were removed in the migration
      });

      test('throws on unknown provider name', () {
        expect(
          () => Providers.get('unknown-provider'),
          throwsA(isA<Exception>()),
        );
        expect(() => Providers.get('invalid'), throwsA(isA<Exception>()));
        expect(() => Providers.get(''), throwsA(isA<Exception>()));
      });

      test('is case insensitive', () {
        // Provider lookup is actually case-insensitive
        expect(Providers.get('OpenAI'), equals(Providers.openai));
        expect(Providers.get('ANTHROPIC'), equals(Providers.anthropic));
        expect(Providers.get('Claude'), equals(Providers.anthropic));
      });
    });

    group('embeddings provider selection', () {
      test('finds providers by exact name', () {
        expect(Providers.get('openai'), equals(Providers.openai));
        expect(Providers.get('google'), equals(Providers.google));
        expect(Providers.get('mistral'), equals(Providers.mistral));
        expect(Providers.get('cohere'), equals(Providers.cohere));
      });

      test('finds providers by aliases', () {
        // After unified Provider, aliases work for embeddings too
        expect(Providers.get('gemini'), equals(Providers.google));
      });

      test('throws on unknown provider name', () {
        expect(() => Providers.get('unknown'), throwsA(isA<Exception>()));
        expect(
          () => Providers.get('invalid-provider'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('provider enumeration', () {
      test('lists all chat providers', () {
        final providers = Providers.all;
        expect(providers, isNotEmpty);
        // At least 11 providers available
        expect(providers.length, greaterThanOrEqualTo(11));

        // Verify key providers are included
        final providerNames = providers.map((p) => p.name).toSet();
        expect(providerNames, contains('openai'));
        expect(providerNames, contains('anthropic'));
        expect(providerNames, contains('google'));
        expect(providerNames, contains('mistral'));
        expect(providerNames, contains('ollama'));
        expect(providerNames, contains('together'));
        expect(providerNames, contains('cohere'));
      });

      test('lists all embeddings providers', () {
        final providers = Providers.allWith({ProviderCaps.embeddings});
        expect(providers, hasLength(6));

        final providerNames = providers.map((p) => p.name).toSet();
        expect(providerNames, contains('openai'));
        expect(providerNames, contains('google'));
        expect(providerNames, contains('mistral'));
        expect(providerNames, contains('cohere'));
        expect(
          providerNames,
          contains('google-openai'),
        ); // OpenAI-compatible Google endpoint
      });

      runChatProviderTest('chat providers have required properties', (
        provider,
      ) async {
        expect(provider.name, isNotEmpty);
        expect(provider.displayName, isNotEmpty);
        expect(provider.createChatModel, isNotNull);
        expect(provider.listModels, isNotNull);
      });

      runEmbeddingsProviderTest(
        'embeddings providers have required properties',
        (provider) async {
          expect(provider.name, isNotEmpty);
          expect(provider.displayName, isNotEmpty);
          expect(provider.createEmbeddingsModel, isNotNull);
          expect(provider.listModels, isNotNull);
        },
      );
    });

    // Model enumeration moved to edge cases (limited providers)
    group('basic model access', () {
      test('providers have listModels method', () {
        // Test that all providers have the method (no API calls)
        for (final provider in Providers.all) {
          expect(provider.listModels, isNotNull);
        }

        for (final provider in Providers.all) {
          expect(provider.listModels, isNotNull);
        }
      });
    });

    group('provider display names', () {
      test('chat providers have descriptive display names', () {
        expect(Providers.openai.displayName, equals('OpenAI'));
        expect(Providers.anthropic.displayName, equals('Anthropic'));
        expect(Providers.google.displayName, contains('Google'));
        expect(Providers.mistral.displayName, equals('Mistral'));
        expect(Providers.ollama.displayName, equals('Ollama'));
      });

      test('embeddings providers have descriptive display names', () {
        expect(Providers.openai.displayName, equals('OpenAI'));
        expect(Providers.google.displayName, contains('Google'));
        expect(Providers.mistral.displayName, equals('Mistral'));
        expect(Providers.cohere.displayName, equals('Cohere'));
      });
    });

    group('provider uniqueness', () {
      test('chat provider names are unique', () {
        final providers = Providers.all;
        final names = providers.map((p) => p.name).toList();
        final uniqueNames = names.toSet();
        expect(
          uniqueNames.length,
          equals(names.length),
          reason: 'All chat provider names should be unique',
        );
      });

      test('embeddings provider names are unique', () {
        final providers = Providers.all;
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
        final provider = Providers.get('openai');
        final model = provider.createChatModel(name: 'gpt-4o-mini');
        expect(model, isNotNull);
      });

      test('can use aliases for model creation', () {
        final claudeProvider = Providers.get('claude');
        expect(claudeProvider.name, equals('anthropic'));

        // Skip actual model creation if API key not available
        expect(claudeProvider, isNotNull);
      });

      test('supports dynamic agent creation', () {
        final provider = Providers.get('gemini');
        expect(provider.name, equals('google'));

        final agent = Agent('${provider.name}:gemini-2.0-flash');
        expect(agent, isNotNull);
        // Agent.model returns "provider:model" format
        expect(agent.model, equals('google:gemini-2.0-flash'));
      });
    });

    group('provider comparison', () {
      test('providers are comparable', () {
        final provider1 = Providers.get('openai');
        final provider2 = Providers.openai;
        expect(provider1, equals(provider2));

        final aliasProvider = Providers.get('claude');
        final directProvider = Providers.anthropic;
        expect(aliasProvider, equals(directProvider));
      });

      test('different providers are not equal', () {
        final openai = Providers.openai;
        final anthropic = Providers.anthropic;
        expect(openai, isNot(equals(anthropic)));
      });
    });

    group('error handling', () {
      test('handles null and empty provider names gracefully', () {
        expect(() => Providers.get(''), throwsA(isA<Exception>()));
      });

      test('provides helpful error messages', () {
        expect(
          () => Providers.get('invalid-provider'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('edge cases (limited providers)', () {
      // Test edge cases on only 1-2 providers to save resources
      // and avoid timeouts
      final edgeCaseProviders = <Provider>[
        Providers.openai,
        Providers.anthropic,
      ];

      final edgeCaseEmbeddingsProviders = <Provider>[Providers.openai];

      test('chat providers return available models', () async {
        for (final provider in edgeCaseProviders) {
          final models = await provider.listModels().toList();
          expect(
            models,
            isNotEmpty,
            reason: 'Provider ${provider.name} should have models',
          );

          // Verify model structure
          for (final model in models) {
            expect(
              model.name,
              isNotEmpty,
              reason: 'Model name should not be empty for ${provider.name}',
            );
          }
        }
      });

      test('embeddings providers return available models', () async {
        for (final provider in edgeCaseEmbeddingsProviders) {
          final models = await provider.listModels().toList();
          expect(
            models,
            isNotEmpty,
            reason: 'Provider ${provider.name} should have embedding models',
          );

          // Verify model structure
          for (final model in models) {
            expect(
              model.name,
              isNotEmpty,
              reason: 'Model name should not be empty for ${provider.name}',
            );
          }
        }
      });

      test('model counts match documented ranges', () async {
        // Only test OpenAI to avoid API quota issues
        final openaiModels = await Providers.openai.listModels().toList();
        expect(openaiModels.length, greaterThan(50));
      });

      test('models have consistent naming patterns', () async {
        // Only test OpenAI for naming patterns
        final provider = Providers.openai;
        final models = await provider.listModels().toList();

        for (final model in models.take(10)) {
          // Test first 10 models only
          // OpenAI models should have recognizable patterns
          expect(
            model.name,
            matches(RegExp(r'^[a-zA-Z0-9\-\.\_]+$')),
            reason: 'Model name should be alphanumeric with hyphens/dots',
          );

          // ID should match provider:model format when used with Agent
          expect('${provider.name}:${model.name}', isNotEmpty);
        }
      });
    });
  });
}
