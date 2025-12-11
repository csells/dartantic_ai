import 'dart:typed_data';

import 'package:dartantic_ai/src/chat_models/openai_responses/openai_responses_event_mapper.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:openai_core/openai_core.dart' as openai;
import 'package:test/test.dart';

// Mock download function for tests
Future<ContainerFileData> _mockDownloadContainerFile(
  String containerId,
  String fileId,
) async => ContainerFileData(
  bytes: Uint8List.fromList(const [1, 2, 3, 4]),
  fileName: '$fileId.bin',
);

void main() {
  group('OpenAIResponsesEventMapper thinking metadata', () {
    test(
      'emits thinking text in ChatResult metadata during streaming',
      () async {
        final mapper = OpenAIResponsesEventMapper(
          storeSession: false,
          downloadContainerFile: _mockDownloadContainerFile,
        );

        // Simulate reasoning summary text delta event
        const thinkingEvent = openai.ResponseReasoningSummaryTextDelta(
          itemId: 'reasoning_1',
          outputIndex: 0,
          summaryIndex: 0,
          delta: 'I am thinking about quicksort...',
          sequenceNumber: 1,
        );

        final results = await mapper.handle(thinkingEvent).toList();

        expect(results, hasLength(1));
        final result = results.first;

        // Thinking should be surfaced via ChatResult.thinking, not metadata
        expect(result.thinking, equals('I am thinking about quicksort...'));
        expect(result.output.parts, isEmpty);
        expect(result.messages, isEmpty);
      },
    );

    test('filters reasoning text from regular output stream', () async {
      final mapper = OpenAIResponsesEventMapper(
        storeSession: false,
        downloadContainerFile: _mockDownloadContainerFile,
      );

      // First, add a Reasoning item at outputIndex 0
      const reasoningItemEvent = openai.ResponseOutputItemAdded(
        item: openai.Reasoning(id: 'reasoning_1', summary: []),
        outputIndex: 0,
        sequenceNumber: 1,
      );
      await mapper.handle(reasoningItemEvent).toList();

      // Then, text delta at outputIndex 0 should be skipped (not emitted)
      // because reasoning text comes through ResponseReasoningSummaryTextDelta
      const textDeltaEvent = openai.ResponseOutputTextDelta(
        itemId: 'item_0',
        outputIndex: 0,
        contentIndex: 0,
        delta: 'This is reasoning text',
        sequenceNumber: 2,
      );
      final results = await mapper.handle(textDeltaEvent).toList();

      // Should be empty - reasoning text is skipped from
      // ResponseOutputTextDelta
      expect(
        results,
        isEmpty,
        reason: 'Reasoning text deltas should be filtered out',
      );
    });

    test('allows regular text to stream normally', () async {
      final mapper = OpenAIResponsesEventMapper(
        storeSession: false,
        downloadContainerFile: _mockDownloadContainerFile,
      );

      // Add an OutputMessage item at outputIndex 0 (not reasoning)
      const outputItemEvent = openai.ResponseOutputItemAdded(
        item: openai.OutputMessage(
          id: 'msg_1',
          role: 'assistant',
          content: [],
          status: 'completed',
        ),
        outputIndex: 0,
        sequenceNumber: 1,
      );
      await mapper.handle(outputItemEvent).toList();

      // Text delta at outputIndex 0 should be regular text
      const textDeltaEvent = openai.ResponseOutputTextDelta(
        itemId: 'item_0',
        outputIndex: 0,
        contentIndex: 0,
        delta: 'This is regular response text',
        sequenceNumber: 2,
      );
      final results = await mapper.handle(textDeltaEvent).toList();

      expect(results, hasLength(1));
      final result = results.first;

      // Should be in output parts, not in metadata
      expect(result.output.parts, hasLength(1));
      expect(
        (result.output.parts.first as TextPart).text,
        equals('This is regular response text'),
      );
      expect(result.metadata['thinking'], isNull);
    });
  });
}
