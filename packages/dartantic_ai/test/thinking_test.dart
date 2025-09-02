/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

void main() {
  group(
    'Thinking (OpenAI Responses)',
    timeout: const Timeout(Duration(minutes: 3)),
    () {
      test(
        'streams thinking-first and thinking-only metadata chunks',
        () async {
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

          await for (final chunk in agent.sendStream(
            'In one sentence: how does quicksort work?',
          )) {
            final thinking = chunk.metadata['thinking'];
            final isThinkingOnly =
                chunk.output.isEmpty &&
                thinking is String &&
                thinking.isNotEmpty;

            if (isThinkingOnly) {
              sawThinkingOnly = true;
              if (!sawAnyText) sawThinkingBeforeText = true;
            }

            if (chunk.output.isNotEmpty) {
              sawAnyText = true;
              // First text chunk is sufficient to validate ordering
              break;
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
        },
      );

      // Note: We intentionally avoid checking final-result metadata because
      // thinking deltas are streamed live and not re-emitted at completion.
    },
  );
}
