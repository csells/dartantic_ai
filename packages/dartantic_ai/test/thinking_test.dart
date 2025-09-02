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

void main() {
  void runProviderTest(
    String description,
    Future<void> Function(Provider provider) testFunction, {
    Set<ProviderCaps>? requiredCaps,
    bool edgeCase = false,
  }) {
    final providers = edgeCase
        ? ['google:gemini-2.0-flash']
        : Providers.all
              .where(
                (p) =>
                    requiredCaps == null ||
                    requiredCaps.every((cap) => p.caps.contains(cap)),
              )
              .map((p) => '${p.name}:${p.defaultModelNames[ModelKind.chat]}');

    for (final providerModel in providers) {
      test('$providerModel: $description', () async {
        final parts = providerModel.split(':');
        final providerName = parts[0];
        final provider = Providers.get(providerName);
        await testFunction(provider);
      });
    }
  }

  group('Thinking', timeout: const Timeout(Duration(minutes: 3)), () {
    runProviderTest(
      'streams thinking-only metadata when present',
      (provider) async {
        final agent = Agent(
          provider.name,
          chatModelOptions: const OpenAIResponsesChatOptions(
            reasoningEffort: OpenAIReasoningEffort.high,
          ),
        );

        var sawThinkingOnly = false;
        var sawAnyText = false;

        await for (final chunk in agent.sendStream(
          'Solve 247 + 389. Think step by step, then give the final answer.',
        )) {
          final thinking = chunk.metadata['thinking'];
          if (chunk.output.isEmpty &&
              thinking is String &&
              thinking.isNotEmpty) {
            sawThinkingOnly = true;
            break; // Found a thinking-only delta
          }
          if (chunk.output.isNotEmpty) {
            sawAnyText = true;
          }
        }

        expect(sawAnyText, isTrue);
        expect(sawThinkingOnly, isTrue);
      },
      requiredCaps: {ProviderCaps.thinking},
    );

    runProviderTest(
      'final thinking present and excluded from history',
      (provider) async {
        final agent = Agent(
          provider.name,
          chatModelOptions: const OpenAIResponsesChatOptions(
            reasoningEffort: OpenAIReasoningEffort.medium,
          ),
        );

        final result = await agent.send('What is 2 + 2? Explain briefly.');

        final thinking = result.metadata['thinking'];
        expect(thinking, isA<String>());
        expect((thinking as String).isNotEmpty, isTrue);

        // Ensure no ChatMessage contains 'thinking' text injected into content
        for (final msg in result.messages) {
          expect(
            msg.parts.whereType<TextPart>().every(
              (p) => !p.text.contains('thinking:'),
            ),
            isTrue,
          );
        }
      },
      requiredCaps: {ProviderCaps.thinking},
    );
  });
}
