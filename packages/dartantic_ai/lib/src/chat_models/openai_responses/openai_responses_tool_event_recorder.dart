import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import 'openai_responses_event_mapping_state.dart';
import 'openai_responses_tool_types.dart';

/// Records and streams tool execution events from OpenAI Responses API.
///
/// Handles recording tool events to state and yielding them as metadata chunks
/// that can be streamed to consumers for real-time tool execution visibility.
class OpenAIResponsesToolEventRecorder {
  /// Creates a new tool event recorder.
  const OpenAIResponsesToolEventRecorder();

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses.tool_recorder',
  );

  /// Records tool events based on the event type and yields metadata chunks.
  Stream<ChatResult<ChatMessage>> recordToolEventIfNeeded(
    openai.ResponseEvent event,
    EventMappingState state,
  ) async* {
    if (event is openai.ResponseImageGenerationCallPartialImage ||
        event is openai.ResponseImageGenerationCallInProgress ||
        event is openai.ResponseImageGenerationCallGenerating ||
        event is openai.ResponseImageGenerationCallCompleted) {
      recordToolEvent(OpenAIResponsesToolTypes.imageGeneration, event, state);
      yield* yieldToolMetadataChunk(
        OpenAIResponsesToolTypes.imageGeneration,
        event,
      );
      return;
    }

    if (event is openai.ResponseWebSearchCallInProgress ||
        event is openai.ResponseWebSearchCallSearching ||
        event is openai.ResponseWebSearchCallCompleted) {
      yield* handleStandardToolEvent(
        OpenAIResponsesToolTypes.webSearch,
        event,
        state,
      );
      return;
    }

    if (event is openai.ResponseFileSearchCallInProgress ||
        event is openai.ResponseFileSearchCallSearching ||
        event is openai.ResponseFileSearchCallCompleted) {
      yield* handleStandardToolEvent(
        OpenAIResponsesToolTypes.fileSearch,
        event,
        state,
      );
      return;
    }

    if (event is openai.ResponseMcpCallArgumentsDelta ||
        event is openai.ResponseMcpCallArgumentsDone ||
        event is openai.ResponseMcpCallInProgress ||
        event is openai.ResponseMcpCallCompleted ||
        event is openai.ResponseMcpCallFailed ||
        event is openai.ResponseMcpListToolsInProgress ||
        event is openai.ResponseMcpListToolsCompleted ||
        event is openai.ResponseMcpListToolsFailed) {
      yield* handleStandardToolEvent(
        OpenAIResponsesToolTypes.mcp,
        event,
        state,
      );
      return;
    }

    if (event is openai.ResponseCodeInterpreterCallInProgress ||
        event is openai.ResponseCodeInterpreterCallCompleted ||
        event is openai.ResponseCodeInterpreterCallInterpreting) {
      yield* handleStandardToolEvent(
        OpenAIResponsesToolTypes.codeInterpreter,
        event,
        state,
      );
      return;
    }

    _logger.warning(
      'Unhandled Responses event in tool recorder: ${event.runtimeType}',
    );
  }

  /// Records a tool event in the state's tool event log.
  void recordToolEvent(
    String toolType,
    openai.ResponseEvent event,
    EventMappingState state,
  ) {
    state.recordToolEvent(toolType, event.toJson());
  }

  /// Yields a metadata chunk containing the tool event.
  ///
  /// Converts the event to JSON and wraps it in a ChatResult with metadata
  /// following the thinking pattern (always emit as list for consistency).
  Stream<ChatResult<ChatMessage>> yieldToolMetadataChunk(
    String toolKey,
    Object eventOrMap,
  ) async* {
    // Convert to JSON - handle both event objects and maps
    final Map<String, Object?> eventJson;
    if (eventOrMap is openai.ResponseEvent) {
      eventJson = eventOrMap.toJson();
    } else if (eventOrMap is Map<String, Object?>) {
      eventJson = eventOrMap;
    } else {
      throw ArgumentError(
        'Expected ResponseEvent or Map, got ${eventOrMap.runtimeType}',
      );
    }

    // Yield a metadata-only chunk with the event as a single-item list
    // Following the thinking pattern: always emit as list for consistency
    yield ChatResult<ChatMessage>(
      output: const ChatMessage(
        role: ChatMessageRole.model,
        parts: [], // No text parts - just metadata
      ),
      messages: const [],
      metadata: {
        toolKey: [eventJson], // Single-item list
      },
      usage: null,
    );
  }

  /// Helper to record and yield tool events for standard tool types.
  Stream<ChatResult<ChatMessage>> handleStandardToolEvent(
    String toolKey,
    openai.ResponseEvent event,
    EventMappingState state,
  ) async* {
    recordToolEvent(toolKey, event, state);
    yield* yieldToolMetadataChunk(toolKey, event);
  }
}
