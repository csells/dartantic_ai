import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../openai_responses_event_mapping_state.dart';
import 'openai_responses_event_handler.dart';

/// Handles text delta and completion events.
class TextEventHandler implements OpenAIResponsesEventHandler {
  /// Creates a new text event handler.
  const TextEventHandler();

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses.event_handlers.text',
  );

  @override
  bool canHandle(openai.ResponseEvent event) =>
      event is openai.ResponseOutputTextDelta ||
      event is openai.ResponseOutputTextDone;

  @override
  Stream<ChatResult<ChatMessage>> handle(
    openai.ResponseEvent event,
    EventMappingState state,
  ) async* {
    if (event is openai.ResponseOutputTextDelta) {
      yield* _handleTextDelta(event, state);
    }
    // ResponseOutputTextDone requires no action
  }

  Stream<ChatResult<ChatMessage>> _handleTextDelta(
    openai.ResponseOutputTextDelta event,
    EventMappingState state,
  ) async* {
    if (event.delta.isEmpty) {
      return;
    }

    if (state.reasoningOutputIndices.contains(event.outputIndex)) {
      _logger.fine(
        'Skipping reasoning text delta at index ${event.outputIndex}: '
        '"${event.delta}"',
      );
      return;
    }

    _logger.fine(
      'ResponseOutputTextDelta: outputIndex=${event.outputIndex}, '
      'delta="${event.delta}"',
    );

    state.hasStreamedText = true;
    state.streamedTextBuffer.write(event.delta);

    final deltaMessage = ChatMessage(
      role: ChatMessageRole.model,
      parts: [TextPart(event.delta)],
    );
    yield ChatResult<ChatMessage>(
      output: deltaMessage,
      messages: const [],
      metadata: const {},
      usage: null,
    );
  }
}
