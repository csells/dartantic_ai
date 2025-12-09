import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../openai_responses_attachment_collector.dart';
import '../openai_responses_event_mapping_state.dart';
import '../openai_responses_tool_event_recorder.dart';
import '../openai_responses_tool_types.dart';
import 'openai_responses_event_handler.dart';

/// Handles output item lifecycle events (added/done).
class OutputItemEventHandler implements OpenAIResponsesEventHandler {
  /// Creates a new output item event handler.
  const OutputItemEventHandler({
    required this.attachments,
    required this.toolRecorder,
  });

  /// Attachment collector for resolving container files and images.
  final AttachmentCollector attachments;

  /// Tool event recorder for streaming tool execution events.
  final OpenAIResponsesToolEventRecorder toolRecorder;

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses.event_handlers.output_item',
  );

  @override
  bool canHandle(openai.ResponseEvent event) =>
      event is openai.ResponseOutputItemAdded ||
      event is openai.ResponseOutputItemDone;

  @override
  Stream<ChatResult<ChatMessage>> handle(
    openai.ResponseEvent event,
    EventMappingState state,
  ) async* {
    if (event is openai.ResponseOutputItemAdded) {
      _handleOutputItemAdded(event, state);
    } else if (event is openai.ResponseOutputItemDone) {
      yield* _handleOutputItemDone(event, state);
    }
  }

  void _handleOutputItemAdded(
    openai.ResponseOutputItemAdded event,
    EventMappingState state,
  ) {
    final item = event.item;
    _logger.fine('ResponseOutputItemAdded: item type = ${item.runtimeType}');
    if (item is openai.FunctionCall) {
      state.functionCalls[event.outputIndex] = StreamingFunctionCall(
        itemId: item.id ?? 'item_${event.outputIndex}',
        callId: item.callId,
        name: item.name,
        outputIndex: event.outputIndex,
      );
      _logger.fine(
        'Function call created: ${item.name} '
        '(id=${item.callId}) at index ${event.outputIndex}',
      );
      return;
    }

    if (item is openai.Reasoning) {
      _logger.fine('Reasoning item at index ${event.outputIndex}');
      state.reasoningOutputIndices.add(event.outputIndex);
      return;
    }

    if (item is openai.ImageGenerationCall) {
      _logger.fine('Image generation call at index ${event.outputIndex}');
    }
  }

  Stream<ChatResult<ChatMessage>> _handleOutputItemDone(
    openai.ResponseOutputItemDone event,
    EventMappingState state,
  ) async* {
    final item = event.item;
    _logger.fine('ResponseOutputItemDone: item type = ${item.runtimeType}');

    if (item is openai.ImageGenerationCall) {
      _logger.fine('Image generation completed at index ${event.outputIndex}');
      attachments.markImageGenerationCompleted(
        index: event.outputIndex,
        resultBase64: item.resultBase64,
      );
    }

    if (item is openai.CodeInterpreterCall) {
      _logger.fine('Code interpreter completed at index ${event.outputIndex}');
      _logger.fine(
        'CodeInterpreterCall details: containerId=${item.containerId}, '
        'results=${item.results?.length ?? 0}, status=${item.status}',
      );

      // Extract file outputs from code interpreter results
      final containerId = item.containerId;
      if (containerId != null && item.results != null) {
        for (final result in item.results!) {
          if (result is openai.CodeInterpreterFiles) {
            for (final file in result.files) {
              final fileId = file.fileId ?? file.id;
              if (fileId != null) {
                _logger.info(
                  'Found code interpreter file output: '
                  'container_id=$containerId, file_id=$fileId',
                );
                attachments.trackContainerCitation(
                  containerId: containerId,
                  fileId: fileId,
                );
              }
            }
          }
        }
      }

      toolRecorder.recordToolEvent(
        OpenAIResponsesToolTypes.codeInterpreter,
        event,
        state,
      );
      yield* toolRecorder.yieldToolMetadataChunk(
        OpenAIResponsesToolTypes.codeInterpreter,
        event,
      );
    }
  }
}
