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
  group('Provider Capabilities', () {
    group('capability declarations (80% cases)', () {
      test('all providers declare capabilities', () {
        for (final provider in Providers.all) {
          expect(
            provider.caps,
            isNotNull,
            reason: '${provider.name} should have capabilities',
          );
          expect(
            provider.caps,
            isA<Set<ProviderCaps>>(),
            reason: '${provider.name} capabilities should be a Set',
          );
        }
      });

      test('basic chat capability is universal', () {
        for (final provider in Providers.all) {
          expect(
            provider.caps.contains(ProviderCaps.chat),
            isTrue,
            reason: '${provider.name} should support basic chat',
          );
        }
      });

      test('tool capability filter returns providers', () {
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

      test('multi-tool + typed output filter returns providers', () {
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
    });

    group('capability enforcement (80% cases)', () {
      test(
        'providers without tool support reject tools at model level',
        () async {
          // Find a provider without tool support
          final noToolProviders = Providers.all.where(
            (p) => !p.caps.contains(ProviderCaps.multiToolCalls),
          );

          if (noToolProviders.isNotEmpty) {
            final provider = noToolProviders.first;

            // Agent creation should succeed
            final agent = Agent(
              provider.name,
              tools: [
                Tool<String>(
                  name: 'test',
                  description: 'test',
                  inputFromJson: (json) => '',
                  onCall: (input) => '',
                ),
              ],
            );

            // But using the agent should throw at the model level
            // Different models may throw different error types
            expect(
              () => agent.send('Use the test tool'),
              throwsA(anyOf(isA<UnsupportedError>(), isA<ArgumentError>())),
            );
          }
        },
      );

      test('capability checks are accurate', () async {
        // Test that declared capabilities actually work
        final toolProvider = Providers.allWith({
          ProviderCaps.multiToolCalls,
        }).first;

        final tool = Tool<String>(
          name: 'echo',
          description: 'Echo input',
          inputFromJson: (json) => (json['text'] ?? 'test') as String,
          onCall: (input) => input,
        );

        final agent = Agent(toolProvider.name, tools: [tool]);

        // Should work without throwing
        final result = await agent.send('Use echo to say "test"');
        expect(result.output, isNotEmpty);
      });
    });

    group('capability coverage (80% cases)', () {
      test('chat is universally supported', () {
        final chatProviders = Providers.allWith({ProviderCaps.chat});

        // All providers should support chat
        expect(chatProviders.length, equals(Providers.all.length));
      });

      test('tool support coverage', () {
        final toolProviders = Providers.allWith({ProviderCaps.multiToolCalls});

        // Many providers should support tools
        expect(toolProviders.length, greaterThan(5));

        // Known tool-supporting providers
        final toolProviderNames = toolProviders.map((p) => p.name).toSet();
        expect(toolProviderNames, contains('openai'));
        expect(toolProviderNames, contains('anthropic'));
        expect(toolProviderNames, contains('google'));
      });

      test('typed output support', () {
        final typedProviders = Providers.allWith({ProviderCaps.typedOutput});

        // Several providers should support typed output
        expect(typedProviders, isNotEmpty);

        // Known typed output providers
        final typedProviderNames = typedProviders.map((p) => p.name).toSet();
        expect(typedProviderNames, contains('openai'));
      });
    });

    group('capability combinations (80% cases)', () {
      test('providers can have multiple capabilities', () {
        // Find providers with multiple capabilities
        final multiCapProviders = Providers.all.where((p) => p.caps.length > 2);

        expect(multiCapProviders, isNotEmpty);

        // OpenAI should have multiple capabilities
        final openai = Providers.get('openai');
        expect(openai.caps.length, greaterThanOrEqualTo(2));
        expect(openai.caps, contains(ProviderCaps.chat));
        expect(openai.caps, contains(ProviderCaps.multiToolCalls));
      });

      test('capability sets are consistent', () {
        for (final provider in Providers.all) {
          // All providers should at least support chat
          expect(provider.caps, contains(ProviderCaps.chat));

          // Capability sets should not be empty
          expect(provider.caps, isNotEmpty);
        }
      });
    });

    group('edge cases', () {
      test('empty capability filter returns all providers', () {
        final allProviders = Providers.allWith({});
        expect(allProviders.length, equals(Providers.all.length));
      });

      test('non-existent capability filter returns empty', () {
        // Create a filter that no provider satisfies
        final providers = Providers.all
            .where(
              (p) =>
                  p.caps.contains(ProviderCaps.multiToolCalls) &&
                  !p.caps.contains(ProviderCaps.chat),
            )
            .toList();

        expect(providers, isEmpty);
      });

      test('capability declarations are immutable', () {
        final provider = Providers.openai;
        final caps = provider.caps;

        // Capability set should be unmodifiable
        // Trying to add to an unmodifiable set should throw
        expect(
          () => (caps as dynamic).add(ProviderCaps.typedOutput),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('provider capabilities match documentation', () {
        // Spot check some known capabilities
        expect(
          Providers.openai.caps,
          containsAll([ProviderCaps.chat, ProviderCaps.multiToolCalls]),
        );

        expect(
          Providers.anthropic.caps,
          containsAll([ProviderCaps.chat, ProviderCaps.multiToolCalls]),
        );

        expect(Providers.mistral.caps, contains(ProviderCaps.chat));
      });
    });
  });
}
