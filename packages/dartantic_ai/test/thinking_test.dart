/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart'
    show ChatMessageRole;
import 'package:test/test.dart';

void main() {
  group(
    'Thinking (OpenAI Responses)',
    timeout: const Timeout(Duration(minutes: 3)),
    () {
      test('streams thinking deltas and attaches consolidated thinking to '
          'assistant message', () async {
        final agent = Agent(
          'openai-responses',
          chatModelOptions: const OpenAIResponsesChatOptions(
            // Opt-in to summary thinking to exercise the channel
            reasoningSummary: OpenAIReasoningSummary.detailed,
          ),
        );

        var sawAnyText = false;
        var sawThinkingOnly = false;
        var sawThinkingBeforeText = false;
        var sawConsolidatedThinkingOnMessage = false;

        await for (final chunk in agent.sendStream(
          'In one sentence: how does quicksort work?',
        )) {
          final thinking = chunk.metadata['thinking'];
          final isThinkingOnly =
              chunk.output.isEmpty && thinking is String && thinking.isNotEmpty;

          if (isThinkingOnly) {
            sawThinkingOnly = true;
            if (!sawAnyText) sawThinkingBeforeText = true;
          }

          if (chunk.output.isNotEmpty) {
            sawAnyText = true;
          }

          // When a model message is yielded, it should include consolidated
          // thinking
          for (final m in chunk.messages) {
            if (m.role == ChatMessageRole.model) {
              final consolidated = m.metadata['thinking'];
              if (consolidated is String && consolidated.isNotEmpty) {
                sawConsolidatedThinkingOnMessage = true;
              }
            }
          }
        }

        expect(
          sawThinkingOnly,
          isTrue,
          reason: 'Expected metadata-only thinking deltas',
        );
        expect(
          sawAnyText,
          isTrue,
          reason: 'Expected some visible response text',
        );
        expect(
          sawThinkingBeforeText,
          isTrue,
          reason: 'Expected thinking to precede text',
        );
        expect(
          sawConsolidatedThinkingOnMessage,
          isTrue,
          reason:
              'Expected consolidated thinking on the assistant message '
              'metadata',
        );
      });

      test(
        'non-stream: attaches full thinking to result metadata and assistant '
        'message metadata',
        () async {
          final agent = Agent(
            'openai-responses',
            chatModelOptions: const OpenAIResponsesChatOptions(
              reasoningSummary: OpenAIReasoningSummary.detailed,
            ),
          );

          final result = await agent.send(
            'In one sentence: how does quicksort work?',
          );

          final fullThinking = result.metadata['thinking'];
          expect(
            fullThinking is String && fullThinking.isNotEmpty,
            isTrue,
            reason: 'Expected full thinking string on final result metadata',
          );

          // Ensure assistant message has consolidated thinking metadata
          final modelMessages = result.messages
              .where((m) => m.role == ChatMessageRole.model)
              .toList();
          expect(
            modelMessages.isNotEmpty,
            isTrue,
            reason: 'Expected at least one assistant message',
          );

          final hasMessageThinking = modelMessages.any((m) {
            final t = m.metadata['thinking'];
            return t is String && t.isNotEmpty;
          });
          expect(
            hasMessageThinking,
            isTrue,
            reason:
                'Expected consolidated thinking on assistant message metadata',
          );
        },
      );
    },
  );
}
