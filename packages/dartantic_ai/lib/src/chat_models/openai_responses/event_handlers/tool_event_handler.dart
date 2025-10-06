import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../openai_responses_attachment_collector.dart';
import '../openai_responses_event_mapping_state.dart';
import '../openai_responses_tool_event_recorder.dart';
import '../openai_responses_tool_types.dart';
import 'openai_responses_event_handler.dart';

/// Handles server-side tool events (image generation, code interpreter).
class ToolEventHandler implements OpenAIResponsesEventHandler {
  /// Creates a new tool event handler.
  const ToolEventHandler({
    required this.attachments,
    required this.toolRecorder,
  });

  /// Attachment collector for resolving container files and images.
  final AttachmentCollector attachments;

  /// Tool event recorder for streaming tool execution events.
  final OpenAIResponsesToolEventRecorder toolRecorder;

  @override
  bool canHandle(openai.ResponseEvent event) =>
      event is openai.ResponseImageGenerationCallPartialImage ||
      event is openai.ResponseImageGenerationCallCompleted ||
      event is openai.ResponseCodeInterpreterCallCodeDelta ||
      event is openai.ResponseCodeInterpreterCallCodeDone;

  @override
  Stream<ChatResult<ChatMessage>> handle(
    openai.ResponseEvent event,
    EventMappingState state,
  ) async* {
    if (event is openai.ResponseImageGenerationCallPartialImage) {
      yield* _handleImageGenerationPartial(event, state);
    } else if (event is openai.ResponseImageGenerationCallCompleted) {
      yield* _handleImageGenerationCompleted(event, state);
    } else if (event is openai.ResponseCodeInterpreterCallCodeDelta) {
      yield* _handleCodeInterpreterCodeDelta(event, state);
    } else if (event is openai.ResponseCodeInterpreterCallCodeDone) {
      yield* _handleCodeInterpreterCodeDone(event, state);
    }
  }

  Stream<ChatResult<ChatMessage>> _handleImageGenerationPartial(
    openai.ResponseImageGenerationCallPartialImage event,
    EventMappingState state,
  ) async* {
    attachments.recordPartialImage(
      base64: event.partialImageB64,
      index: event.partialImageIndex,
    );
    yield* toolRecorder.recordToolEventIfNeeded(event, state);
  }

  Stream<ChatResult<ChatMessage>> _handleImageGenerationCompleted(
    openai.ResponseImageGenerationCallCompleted event,
    EventMappingState state,
  ) async* {
    attachments.markImageGenerationCompleted(index: event.outputIndex);
    yield* toolRecorder.recordToolEventIfNeeded(event, state);
  }

  Stream<ChatResult<ChatMessage>> _handleCodeInterpreterCodeDelta(
    openai.ResponseCodeInterpreterCallCodeDelta event,
    EventMappingState state,
  ) async* {
    final itemId = event.itemId;
    state.getCodeInterpreterBuffer(itemId).write(event.delta);
    yield* toolRecorder.yieldToolMetadataChunk(
      OpenAIResponsesToolTypes.codeInterpreter,
      event,
    );
  }

  Stream<ChatResult<ChatMessage>> _handleCodeInterpreterCodeDone(
    openai.ResponseCodeInterpreterCallCodeDone event,
    EventMappingState state,
  ) async* {
    final itemId = event.itemId;
    final buffer = state.codeInterpreterCodeBuffers[itemId];
    final accumulatedCode = buffer?.toString();

    if (accumulatedCode != null) {
      final completeEvent = {
        'type': 'response.code_interpreter_call_code.delta',
        'item_id': itemId,
        'output_index': event.outputIndex,
        'delta': accumulatedCode,
      };

      state.recordToolEvent(
        OpenAIResponsesToolTypes.codeInterpreter,
        completeEvent,
      );
    }
    state.removeCodeInterpreterBuffer(itemId);

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
