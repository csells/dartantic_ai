/// Tests to verify metadata is not duplicated during streaming.
///
/// This test specifically validates the fix for the bug where response-level
/// metadata (response_id, model, status) was being yielded 4 times instead
/// of once.

import 'package:dartantic_ai/dartantic_ai.dart';

import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('Metadata Duplication Prevention', () {
    test(
      'OpenAI Responses does not duplicate response-level metadata',
      () async {
        final agent = Agent(
          'openai-responses',
          chatModelOptions: const OpenAIResponsesChatModelOptions(
            serverSideTools: {OpenAIServerSideTool.fileSearch},
          ),
        );

        // Accumulate all streaming results
        final results = <ChatResult>[];
        await agent.sendStream('What is 2+2?').forEach(results.add);

        // Verify we got results
        expect(results, isNotEmpty);

        // Verify no metadata is duplicated
        // This would have failed before the fix with an error like:
        // "Duplicate metadata found at result index X: response_id"
        validateNoMetadataDuplicates(results);

        // Additionally verify response-level metadata appears exactly once
        var responseIdCount = 0;
        for (final result in results) {
          if (result.metadata.containsKey('response_id')) {
            responseIdCount++;
          }
        }

        expect(
          responseIdCount,
          1,
          reason:
              'response_id metadata should appear exactly once, not 4 times',
        );
      },
    );

    test('Tool event metadata is not duplicated', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.codeInterpreter},
        ),
      );

      final results = <ChatResult>[];
      await agent.sendStream('Calculate 5 * 5 in Python').forEach(results.add);

      expect(results, isNotEmpty);

      // Verify no metadata duplication
      validateNoMetadataDuplicates(results);
    });

    test('Multiple metadata keys are not duplicated', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {
            OpenAIServerSideTool.codeInterpreter,
            OpenAIServerSideTool.fileSearch,
          },
        ),
      );

      final results = <ChatResult>[];
      await agent.sendStream('Simple test query').forEach(results.add);

      expect(results, isNotEmpty);

      // Verify no metadata duplication across all keys
      validateNoMetadataDuplicates(results);
    });
  });
}
