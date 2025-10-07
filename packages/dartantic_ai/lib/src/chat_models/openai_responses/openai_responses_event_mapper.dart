import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import 'event_handlers/fallback_event_handler.dart';
import 'event_handlers/function_call_event_handler.dart';
import 'event_handlers/openai_responses_event_handler.dart';
import 'event_handlers/output_item_event_handler.dart';
import 'event_handlers/reasoning_event_handler.dart';
import 'event_handlers/terminal_event_handler.dart';
import 'event_handlers/text_event_handler.dart';
import 'event_handlers/tool_event_handler.dart';
import 'openai_responses_attachment_collector.dart';
import 'openai_responses_attachment_types.dart';
import 'openai_responses_event_mapping_state.dart';
import 'openai_responses_tool_event_recorder.dart';

// Re-export for backward compatibility
export 'openai_responses_attachment_types.dart'
    show ContainerFileData, ContainerFileLoader;

/// Maps OpenAI Responses streaming events into dartantic chat results.
///
/// Uses a chain-of-responsibility pattern to delegate event handling to
/// specialized handlers, each responsible for a specific event family.
class OpenAIResponsesEventMapper {
  /// Creates a new mapper configured for a specific stream invocation.
  OpenAIResponsesEventMapper({
    required this.storeSession,
    required ContainerFileLoader downloadContainerFile,
  }) : _attachments = AttachmentCollector(
         logger: _logger,
         containerFileLoader: downloadContainerFile,
       ) {
    _initializeHandlers();
  }

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses.event_mapper',
  );

  /// Whether session persistence is enabled for this request.
  final bool storeSession;

  /// Function to download container files (provided by chat model layer).
  final AttachmentCollector _attachments;

  /// Mutable state for event mapping.
  final EventMappingState _state = EventMappingState();

  /// Tool event recorder for streaming tool execution events.
  final OpenAIResponsesToolEventRecorder _toolRecorder =
      const OpenAIResponsesToolEventRecorder();

  /// Chain of event handlers, ordered by specificity.
  late final List<OpenAIResponsesEventHandler> _handlers;

  void _initializeHandlers() {
    _handlers = [
      TerminalEventHandler(
        storeSession: storeSession,
        attachments: _attachments,
      ),
      OutputItemEventHandler(
        attachments: _attachments,
        toolRecorder: _toolRecorder,
      ),
      const FunctionCallEventHandler(),
      const TextEventHandler(),
      const ReasoningEventHandler(),
      ToolEventHandler(attachments: _attachments, toolRecorder: _toolRecorder),
      FallbackEventHandler(toolRecorder: _toolRecorder),
    ];
  }

  /// Processes a streaming [event] and emits zero or more [ChatResult]s.
  ///
  /// Uses chain-of-responsibility pattern: iterates through handlers until
  /// one accepts and processes the event.
  Stream<ChatResult<ChatMessage>> handle(openai.ResponseEvent event) async* {
    for (final handler in _handlers) {
      if (handler.canHandle(event)) {
        yield* handler.handle(event, _state);
        return;
      }
    }
  }
}
