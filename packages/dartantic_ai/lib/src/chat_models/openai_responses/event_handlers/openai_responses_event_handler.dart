import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../openai_responses_event_mapping_state.dart';

/// Base interface for handling specific OpenAI Responses API event types.
///
/// Each handler is responsible for processing a family of related events
/// (e.g., text deltas, tool calls, terminal events) and yielding zero or
/// more [ChatResult]s.
abstract class OpenAIResponsesEventHandler {
  /// Checks if this handler can process the given [event].
  bool canHandle(openai.ResponseEvent event);

  /// Processes the [event] and yields zero or more [ChatResult]s.
  Stream<ChatResult<ChatMessage>> handle(
    openai.ResponseEvent event,
    EventMappingState state,
  );
}
