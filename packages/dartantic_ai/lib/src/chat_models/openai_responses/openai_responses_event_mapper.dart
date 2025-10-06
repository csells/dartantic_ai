import 'dart:typed_data';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import 'openai_responses_attachment_collector.dart';
import 'openai_responses_event_mapping_state.dart';
import 'openai_responses_message_builder.dart';
import 'openai_responses_message_mapper.dart';
import 'openai_responses_part_mapper.dart';
import 'openai_responses_session_manager.dart';
import 'openai_responses_tool_event_recorder.dart';
import 'openai_responses_tool_types.dart';

/// Loads a container file by identifier and returns its resolved data.
typedef ContainerFileLoader =
    Future<ContainerFileData> Function(String containerId, String fileId);

/// Resolved data for a downloaded container file, including metadata hints.
class ContainerFileData {
  /// Creates a new [ContainerFileData] instance.
  const ContainerFileData({required this.bytes, this.fileName, this.mimeType});

  /// Raw file bytes returned by the API.
  final Uint8List bytes;

  /// Optional filename hint supplied by the provider.
  final String? fileName;

  /// Optional MIME type hint supplied by the provider.
  final String? mimeType;
}

/// Maps OpenAI Responses streaming events into dartantic chat results.
class OpenAIResponsesEventMapper {
  /// Creates a new mapper configured for a specific stream invocation.
  OpenAIResponsesEventMapper({
    required this.modelName,
    required this.storeSession,
    required this.history,
    required ContainerFileLoader downloadContainerFile,
  }) : _attachments = AttachmentCollector(
         logger: _logger,
         containerFileLoader: downloadContainerFile,
       );

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses.event_mapper',
  );

  /// Model name used for this stream.
  final String modelName;

  /// Whether session persistence is enabled for this request.
  final bool storeSession;

  /// Mapping information derived from the conversation history.
  final OpenAIResponsesHistorySegment history;

  /// Function to download container files (provided by chat model layer).
  final AttachmentCollector _attachments;

  /// Mutable state for event mapping.
  final EventMappingState _state = EventMappingState();

  /// Message builder for creating ChatResults.
  final OpenAIResponsesMessageBuilder _messageBuilder =
      const OpenAIResponsesMessageBuilder();

  /// Session manager for metadata operations.
  final OpenAIResponsesSessionManager _sessionManager =
      const OpenAIResponsesSessionManager();

  /// Part mapper for response item conversion.
  final OpenAIResponsesPartMapper _partMapper =
      const OpenAIResponsesPartMapper();

  /// Tool event recorder for streaming tool execution events.
  final OpenAIResponsesToolEventRecorder _toolRecorder =
      const OpenAIResponsesToolEventRecorder();

  /// Processes a streaming [event] and emits zero or more [ChatResult]s.
  Stream<ChatResult<ChatMessage>> handle(openai.ResponseEvent event) async* {
    if (event is openai.ResponseOutputItemAdded) {
      _handleOutputItemAdded(event);
      return;
    }

    if (event is openai.ResponseOutputItemDone) {
      yield* _handleOutputItemDone(event);
      return;
    }

    if (event is openai.ResponseFunctionCallArgumentsDelta) {
      _handleFunctionCallArgumentsDelta(event);
      return;
    }

    if (event is openai.ResponeFunctionCallArgumentsDone) {
      _handleFunctionCallArgumentsDone(event);
      return;
    }

    if (event is openai.ResponseOutputTextDelta) {
      yield* _handleOutputTextDelta(event);
      return;
    }

    if (event is openai.ResponseOutputTextDone) {
      return;
    }

    if (event is openai.ResponseReasoningSummaryTextDelta) {
      yield* _handleReasoningSummaryDelta(event);
      return;
    }

    if (event is openai.ResponseReasoningSummaryPartAdded ||
        event is openai.ResponseReasoningSummaryPartDone ||
        event is openai.ResponseReasoningDelta ||
        event is openai.ResponseReasoningDone) {
      return;
    }

    if (event is openai.ResponseCompleted) {
      yield* _handleResponseCompleted(event);
      return;
    }

    if (event is openai.ResponseFailed) {
      _handleResponseFailed(event);
      return;
    }

    if (event is openai.ResponseImageGenerationCallPartialImage) {
      yield* _handleImageGenerationPartial(event);
      return;
    }

    if (event is openai.ResponseImageGenerationCallCompleted) {
      yield* _handleImageGenerationCompleted(event);
      return;
    }

    if (event is openai.ResponseCodeInterpreterCallCodeDelta) {
      yield* _handleCodeInterpreterCodeDelta(event);
      return;
    }

    if (event is openai.ResponseCodeInterpreterCallCodeDone) {
      yield* _handleCodeInterpreterCodeDone(event);
      return;
    }

    // Delegate all other tool events to the recorder
    yield* _toolRecorder.recordToolEventIfNeeded(event, _state);
  }

  void _handleOutputItemAdded(openai.ResponseOutputItemAdded event) {
    final item = event.item;
    _logger.fine('ResponseOutputItemAdded: item type = ${item.runtimeType}');
    if (item is openai.FunctionCall) {
      _state.functionCalls[event.outputIndex] = StreamingFunctionCall(
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
      _state.reasoningOutputIndices.add(event.outputIndex);
      return;
    }

    if (item is openai.ImageGenerationCall) {
      _logger.fine('Image generation call at index ${event.outputIndex}');
    }
  }

  Stream<ChatResult<ChatMessage>> _handleOutputItemDone(
    openai.ResponseOutputItemDone event,
  ) async* {
    final item = event.item;
    _logger.fine('ResponseOutputItemDone: item type = ${item.runtimeType}');

    if (item is openai.ImageGenerationCall) {
      _logger.fine('Image generation completed at index ${event.outputIndex}');
      _attachments.markImageGenerationCompleted(
        resultBase64: item.resultBase64,
      );
    }

    if (item is openai.CodeInterpreterCall) {
      _logger.fine('Code interpreter completed at index ${event.outputIndex}');
      _toolRecorder.recordToolEvent(
        OpenAIResponsesToolTypes.codeInterpreter,
        event,
        _state,
      );
      yield* _toolRecorder.yieldToolMetadataChunk(
        OpenAIResponsesToolTypes.codeInterpreter,
        event,
      );
    }
  }

  void _handleFunctionCallArgumentsDelta(
    openai.ResponseFunctionCallArgumentsDelta event,
  ) {
    final call = _state.functionCalls[event.outputIndex];
    if (call != null) {
      call.appendArguments(event.delta);
      _logger.fine(
        'Appended arguments delta to call at index '
        '${event.outputIndex}: ${event.delta}',
      );
    } else {
      _logger.warning(
        'No function call found for outputIndex ${event.outputIndex}',
      );
    }
  }

  void _handleFunctionCallArgumentsDone(
    openai.ResponeFunctionCallArgumentsDone event,
  ) {
    _logger.fine(
      'ResponeFunctionCallArgumentsDone for index ${event.outputIndex}',
    );
    final call = _state.functionCalls[event.outputIndex];
    if (call != null) {
      call.arguments = event.arguments;
      _logger.fine(
        'Function call completed: ${call.name} with args: ${event.arguments}',
      );
    } else {
      _logger.warning(
        'No function call found for completion at index ${event.outputIndex}',
      );
    }
  }

  Stream<ChatResult<ChatMessage>> _handleOutputTextDelta(
    openai.ResponseOutputTextDelta event,
  ) async* {
    if (event.delta.isEmpty) {
      return;
    }

    if (_state.reasoningOutputIndices.contains(event.outputIndex)) {
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

    _state.hasStreamedText = true;
    _state.streamedTextBuffer.write(event.delta);

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

  Stream<ChatResult<ChatMessage>> _handleReasoningSummaryDelta(
    openai.ResponseReasoningSummaryTextDelta event,
  ) async* {
    _state.thinkingBuffer.write(event.delta);
    _logger.info('ResponseReasoningSummaryTextDelta: "${event.delta}"');
    yield ChatResult<ChatMessage>(
      output: const ChatMessage(role: ChatMessageRole.model, parts: []),
      messages: const [],
      metadata: {'thinking': event.delta},
      usage: null,
    );
  }

  Stream<ChatResult<ChatMessage>> _handleResponseCompleted(
    openai.ResponseCompleted event,
  ) async* {
    if (_state.finalResultBuilt) {
      return;
    }
    _state.finalResultBuilt = true;
    yield await _buildFinalResult(event.response);
  }

  void _handleResponseFailed(openai.ResponseFailed event) {
    final error = event.response.error;
    if (error != null) {
      throw openai.OpenAIRequestException(
        message: error.message,
        code: error.code,
        param: error.param,
        statusCode: -1,
      );
    }
    throw const openai.OpenAIRequestException(
      message: 'OpenAI Responses request failed',
      statusCode: -1,
    );
  }

  Stream<ChatResult<ChatMessage>> _handleImageGenerationPartial(
    openai.ResponseImageGenerationCallPartialImage event,
  ) async* {
    _attachments.recordPartialImage(
      base64: event.partialImageB64,
      index: event.partialImageIndex,
    );
    yield* _toolRecorder.recordToolEventIfNeeded(event, _state);
  }

  Stream<ChatResult<ChatMessage>> _handleImageGenerationCompleted(
    openai.ResponseImageGenerationCallCompleted event,
  ) async* {
    _attachments.markImageGenerationCompleted();
    yield* _toolRecorder.recordToolEventIfNeeded(event, _state);
  }

  Stream<ChatResult<ChatMessage>> _handleCodeInterpreterCodeDelta(
    openai.ResponseCodeInterpreterCallCodeDelta event,
  ) async* {
    final itemId = event.itemId;
    _state.getCodeInterpreterBuffer(itemId).write(event.delta);
    yield* _toolRecorder.yieldToolMetadataChunk(
      OpenAIResponsesToolTypes.codeInterpreter,
      event,
    );
  }

  Stream<ChatResult<ChatMessage>> _handleCodeInterpreterCodeDone(
    openai.ResponseCodeInterpreterCallCodeDone event,
  ) async* {
    final itemId = event.itemId;
    final buffer = _state.codeInterpreterCodeBuffers[itemId];
    final accumulatedCode = buffer?.toString();

    if (accumulatedCode != null) {
      final completeEvent = {
        'type': 'response.code_interpreter_call_code.delta',
        'item_id': itemId,
        'output_index': event.outputIndex,
        'delta': accumulatedCode,
      };

      _state.recordToolEvent(
        OpenAIResponsesToolTypes.codeInterpreter,
        completeEvent,
      );
    }
    _state.removeCodeInterpreterBuffer(itemId);

    _toolRecorder.recordToolEvent(
      OpenAIResponsesToolTypes.codeInterpreter,
      event,
      _state,
    );
    yield* _toolRecorder.yieldToolMetadataChunk(
      OpenAIResponsesToolTypes.codeInterpreter,
      event,
    );
  }

  /// Maps response items to dartantic Parts.
  ///
  /// Returns a record containing the mapped parts and a mapping of tool call
  /// IDs to their names (needed for mapping function outputs).
  ({List<Part> parts, Map<String, String> toolCallNames}) _mapResponseItems(
    List<openai.ResponseItem> items,
  ) => _partMapper.mapResponseItems(items, _attachments);

  Future<ChatResult<ChatMessage>> _buildFinalResult(
    openai.Response response,
  ) async {
    final parts = await _collectAllParts(response);
    final messageMetadata = _sessionManager.buildSessionMetadata(
      response: response,
      storeSession: storeSession,
    );
    final usage = _mapUsage(response.usage);
    final resultMetadata = _sessionManager.buildResultMetadata(response);
    final finishReason = _mapFinishReason(response);
    final responseId = response.id ?? '';

    _logger.fine('Building final message with ${parts.length} parts');
    for (final part in parts) {
      _logger.fine('  Part: ${part.runtimeType}');
    }

    if (_state.hasStreamedText) {
      return _messageBuilder.createStreamingResult(
        responseId: responseId,
        parts: parts,
        messageMetadata: messageMetadata,
        usage: usage,
        finishReason: finishReason,
        resultMetadata: resultMetadata,
      );
    } else {
      return _messageBuilder.createNonStreamingResult(
        responseId: responseId,
        parts: parts,
        messageMetadata: messageMetadata,
        usage: usage,
        finishReason: finishReason,
        resultMetadata: resultMetadata,
      );
    }
  }

  /// Collects all parts from response output and attachments.
  Future<List<Part>> _collectAllParts(openai.Response response) async {
    final mapped = _mapResponseItems(
      response.output ?? const <openai.ResponseItem>[],
    );
    final parts = [...mapped.parts];

    final attachmentParts = await _attachments.resolveAttachments();
    if (attachmentParts.isNotEmpty) {
      parts.addAll(attachmentParts);
    }

    return parts;
  }

  static LanguageModelUsage _mapUsage(openai.Usage? usage) => usage == null
      ? const LanguageModelUsage()
      : LanguageModelUsage(
          promptTokens: usage.inputTokens,
          responseTokens: usage.outputTokens,
          totalTokens: usage.totalTokens,
        );

  static FinishReason _mapFinishReason(openai.Response response) {
    switch (response.status) {
      case 'completed':
        return FinishReason.stop;
      case 'incomplete':
        final reason = response.incompleteDetails?.reason;
        if (reason == 'max_output_tokens') return FinishReason.length;
        if (reason == 'content_filter') return FinishReason.contentFilter;
        return FinishReason.unspecified;
      default:
        return FinishReason.unspecified;
    }
  }
}
