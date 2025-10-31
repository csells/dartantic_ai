import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../openai_responses_event_mapping_state.dart';
import 'openai_responses_event_handler.dart';

/// Handles reasoning and thinking-related events.
class ReasoningEventHandler implements OpenAIResponsesEventHandler {
  /// Creates a new reasoning event handler.
  const ReasoningEventHandler();

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses.event_handlers.reasoning',
  );

  @override
  bool canHandle(openai.ResponseEvent event) =>
      event is openai.ResponseReasoningSummaryTextDelta ||
      event is openai.ResponseReasoningSummaryPartAdded ||
      event is openai.ResponseReasoningSummaryPartDone ||
      event is openai.ResponseReasoningDelta ||
      event is openai.ResponseReasoningDone;

  @override
  Stream<ChatResult<ChatMessage>> handle(
    openai.ResponseEvent event,
    EventMappingState state,
  ) async* {
    if (event is openai.ResponseReasoningSummaryTextDelta) {
      yield* _handleReasoningSummaryDelta(event, state);
    }
    // Other reasoning events require no action
  }

  Stream<ChatResult<ChatMessage>> _handleReasoningSummaryDelta(
    openai.ResponseReasoningSummaryTextDelta event,
    EventMappingState state,
  ) async* {
    state.thinkingBuffer.write(event.delta);
    _logger.info('ResponseReasoningSummaryTextDelta: "${event.delta}"');
    yield ChatResult<ChatMessage>(
      output: const ChatMessage(role: ChatMessageRole.model, parts: []),
      messages: const [],
      thinking: event.delta,
      usage: null,
    );
  }
}
