import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../openai_responses_event_mapping_state.dart';
import '../openai_responses_tool_event_recorder.dart';
import 'openai_responses_event_handler.dart';

/// Fallback handler for events not handled by specialized handlers.
///
/// Delegates to the tool event recorder for any tool-related events
/// that don't require specific processing.
class FallbackEventHandler implements OpenAIResponsesEventHandler {
  /// Creates a new fallback event handler.
  const FallbackEventHandler({required this.toolRecorder});

  /// Tool event recorder for streaming tool execution events.
  final OpenAIResponsesToolEventRecorder toolRecorder;

  @override
  bool canHandle(openai.ResponseEvent event) => true; // Catch-all

  @override
  Stream<ChatResult<ChatMessage>> handle(
    openai.ResponseEvent event,
    EventMappingState state,
  ) => toolRecorder.recordToolEventIfNeeded(event, state);
}
