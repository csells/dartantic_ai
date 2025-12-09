/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g.
///    ProviderTestCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';

void main() {
  group('Provider Test Capabilities', () {
    group('test capability mapping (80% cases)', () {
      test('all providers have test capability mappings', () {
        for (final provider in Agent.allProviders) {
          final caps = getProviderTestCaps(provider.name);
          expect(
            caps,
            isNotNull,
            reason: '${provider.name} should have test capabilities',
          );
          expect(
            caps,
            isA<Set<ProviderTestCaps>>(),
            reason: '${provider.name} capabilities should be a Set',
          );
        }
      });

      test('basic chat capability is universal in test mapping', () {
        for (final provider in Agent.allProviders) {
          final caps = getProviderTestCaps(provider.name);
          expect(
            caps.contains(ProviderTestCaps.chat),
            isTrue,
            reason: '${provider.name} should support basic chat',
          );
        }
      });

      test('tool capability filter returns providers', () {
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

      test('multi-tool + typed output filter returns providers', () {
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
    });

    group('capability enforcement (80% cases)', () {
      test(
        'providers without tool support reject tools at model level',
        () async {
          // Find a provider without tool support
          final noToolProviders = Agent.allProviders.where(
            (p) =>
                !providerHasTestCaps(p.name, {ProviderTestCaps.multiToolCalls}),
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

            // But using the agent should throw at the model level Different
            // models may throw different error types
            expect(
              () => agent.send('Use the test tool'),
              throwsA(anyOf(isA<UnsupportedError>(), isA<ArgumentError>())),
            );
          }
        },
      );

      test('capability checks are accurate', () async {
        // Test that declared capabilities actually work
        final toolProvider = Agent.allProviders.firstWhere(
          (p) => providerHasTestCaps(p.name, {ProviderTestCaps.multiToolCalls}),
        );

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
        final chatProviders = Agent.allProviders
            .where((p) => providerHasTestCaps(p.name, {ProviderTestCaps.chat}))
            .toList();

        // All providers should support chat
        expect(chatProviders.length, equals(Agent.allProviders.length));
      });

      test('tool support coverage', () {
        final toolProviders = Agent.allProviders
            .where(
              (p) => providerHasTestCaps(p.name, {
                ProviderTestCaps.multiToolCalls,
              }),
            )
            .toList();

        // Many providers should support tools
        expect(toolProviders.length, greaterThan(3));

        // Known tool-supporting providers
        final toolProviderNames = toolProviders.map((p) => p.name).toSet();
        expect(toolProviderNames, contains('openai'));
        expect(toolProviderNames, contains('anthropic'));
        expect(toolProviderNames, contains('google'));
      });

      test('typed output support', () {
        final typedProviders = Agent.allProviders
            .where(
              (p) =>
                  providerHasTestCaps(p.name, {ProviderTestCaps.typedOutput}),
            )
            .toList();

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
        final multiCapProviders = Agent.allProviders.where(
          (p) => getProviderTestCaps(p.name).length > 2,
        );

        expect(multiCapProviders, isNotEmpty);

        // OpenAI should have multiple capabilities
        final openaiCaps = getProviderTestCaps('openai');
        expect(openaiCaps.length, greaterThanOrEqualTo(2));
        expect(openaiCaps, contains(ProviderTestCaps.chat));
        expect(openaiCaps, contains(ProviderTestCaps.multiToolCalls));
      });

      test('capability sets are consistent', () {
        for (final provider in Agent.allProviders) {
          final caps = getProviderTestCaps(provider.name);
          // All providers should at least support chat
          expect(caps, contains(ProviderTestCaps.chat));

          // Capability sets should not be empty
          expect(caps, isNotEmpty);
        }
      });
    });

    group('edge cases', () {
      test('empty capability filter returns all providers', () {
        final allProviders = Agent.allProviders
            .where((p) => providerHasTestCaps(p.name, {}))
            .toList();
        expect(allProviders.length, equals(Agent.allProviders.length));
      });

      test('non-existent capability filter returns empty', () {
        // Create a filter that no provider satisfies
        final providers = Agent.allProviders
            .where(
              (p) =>
                  providerHasTestCaps(p.name, {
                    ProviderTestCaps.multiToolCalls,
                  }) &&
                  !providerHasTestCaps(p.name, {ProviderTestCaps.chat}),
            )
            .toList();

        expect(providers, isEmpty);
      });

      test('provider capabilities match documentation', () {
        // Spot check some known capabilities
        expect(
          getProviderTestCaps('openai'),
          containsAll([ProviderTestCaps.chat, ProviderTestCaps.multiToolCalls]),
        );

        expect(
          getProviderTestCaps('anthropic'),
          containsAll([ProviderTestCaps.chat, ProviderTestCaps.multiToolCalls]),
        );

        expect(getProviderTestCaps('mistral'), contains(ProviderTestCaps.chat));
      });
    });
  });
}
