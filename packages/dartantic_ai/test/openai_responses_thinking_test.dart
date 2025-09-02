import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAI Responses thinking-first', () {
    test(
      'emits thinking-only metadata before text',
      () async {
        final agent = Agent(
          'openai-responses',
          chatModelOptions: const OpenAIResponsesChatOptions(
            reasoningSummary: OpenAIReasoningSummary.detailed,
          ),
        );

        var sawThinking = false;
        var sawTextFirst = false;
        var sawThinkingBeforeText = false;

        await for (final chunk in agent.sendStream(
          'In one sentence: how does quicksort work?',
        )) {
          final thinking = chunk.metadata['thinking'];
          if (thinking is String && thinking.isNotEmpty) {
            if (!sawThinking) {
              sawThinking = true;
              if (!sawTextFirst) {
                sawThinkingBeforeText = true;
              }
            }
          }
          if (chunk.output.isNotEmpty) {
            if (!sawThinking) {
              sawTextFirst = true;
            }
            // We only need the first text chunk to determine ordering
            break;
          }
        }

        expect(
          sawThinking,
          isTrue,
          reason: 'Expected reasoning summary deltas when summary=detailed',
        );
        expect(
          sawThinkingBeforeText,
          isTrue,
          reason: 'Expected thinking to stream before any text',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
