import 'dart:convert';
import 'dart:typed_data';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../../shared/openai_responses_metadata.dart';
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
    // Handle function call item creation
    if (event is openai.ResponseOutputItemAdded) {
      final item = event.item;
      _logger.fine('ResponseOutputItemAdded: item type = ${item.runtimeType}');
      if (item is openai.FunctionCall) {
        // Store initial function call info indexed by outputIndex
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
      } else if (item is openai.Reasoning) {
        // Track that this outputIndex contains reasoning text
        _logger.fine('Reasoning item at index ${event.outputIndex}');
        _state.reasoningOutputIndices.add(event.outputIndex);
      } else if (item is openai.ImageGenerationCall) {
        // Track the output index for image generation
        _logger.fine('Image generation call at index ${event.outputIndex}');
      }
      return;
    }

    if (event is openai.ResponseOutputItemDone) {
      final item = event.item;
      _logger.fine('ResponseOutputItemDone: item type = ${item.runtimeType}');

      // Check if this is image generation completion
      if (item is openai.ImageGenerationCall) {
        _logger.fine(
          'Image generation completed at index ${event.outputIndex}',
        );
        _attachments.markImageGenerationCompleted(
          resultBase64: item.resultBase64,
        );
      }

      // Check if this is code interpreter completion with file results
      if (item is openai.CodeInterpreterCall) {
        _logger.fine(
          'Code interpreter completed at index ${event.outputIndex}',
        );
        // Record the complete code interpreter call with results
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

      return;
    }

    // Handle function call argument streaming
    if (event is openai.ResponseFunctionCallArgumentsDelta) {
      // Find the function call by outputIndex
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
      return;
    }

    // Handle function call completion
    if (event is openai.ResponeFunctionCallArgumentsDone) {
      // Note: typo in class name from openai_core
      _logger.fine(
        'ResponeFunctionCallArgumentsDone for index ${event.outputIndex}',
      );
      final call = _state.functionCalls[event.outputIndex];
      if (call != null) {
        // Set the complete arguments
        call.arguments = event.arguments;
        _logger.fine(
          'Function call completed: ${call.name} '
          'with args: ${event.arguments}',
        );
        // Keep the function call for the final result
        // Don't emit here as it will be handled by ResponseCompleted
      } else {
        _logger.warning(
          'No function call found for completion at index ${event.outputIndex}',
        );
      }
      return;
    }
    if (event is openai.ResponseOutputTextDelta) {
      if (event.delta.isEmpty) return;

      // Check if this text delta belongs to a reasoning item
      if (_state.reasoningOutputIndices.contains(event.outputIndex)) {
        // This is reasoning text - skip it, it will come through
        // ResponseReasoningSummaryTextDelta
        _logger.fine(
          'Skipping reasoning text delta at index ${event.outputIndex}: '
          '"${event.delta}"',
        );
        return;
      }

      // Log the delta to understand what's being streamed
      _logger.fine(
        'ResponseOutputTextDelta: outputIndex=${event.outputIndex}, '
        'delta="${event.delta}"',
      );

      // Track that we've streamed text and accumulate it
      _state.hasStreamedText = true;
      _state.streamedTextBuffer.write(event.delta);

      // Yield ONLY the delta for streaming
      final deltaMessage = ChatMessage(
        role: ChatMessageRole.model,
        parts: [TextPart(event.delta)],
      );
      yield ChatResult<ChatMessage>(
        output: deltaMessage,
        messages: const [], // Empty during streaming - in final result
        metadata: const {},
        usage: const LanguageModelUsage(),
      );
      return;
    }

    if (event is openai.ResponseOutputTextDone) {
      return;
    }

    if (event is openai.ResponseReasoningSummaryTextDelta) {
      _state.thinkingBuffer.write(event.delta);
      _logger.info('ResponseReasoningSummaryTextDelta: "${event.delta}"');
      // Emit the thinking delta in metadata so it can stream
      yield ChatResult<ChatMessage>(
        output: const ChatMessage(
          role: ChatMessageRole.model,
          parts: [], // No text parts - just metadata
        ),
        messages: const [],
        metadata: {
          'thinking': event.delta, // Stream the thinking delta
        },
        usage: const LanguageModelUsage(),
      );
      return;
    }

    if (event is openai.ResponseReasoningSummaryPartAdded) {
      // Just skip - we don't need to track these details
      return;
    }

    if (event is openai.ResponseReasoningSummaryPartDone) {
      // Just skip - we don't need to track these details
      return;
    }

    if (event is openai.ResponseReasoningDelta) {
      // Just skip - we don't need to track these details
      return;
    }

    if (event is openai.ResponseReasoningDone) {
      // Just skip - we don't need to track these details
      return;
    }

    if (event is openai.ResponseCompleted) {
      // Only build final result once to avoid duplication
      if (!_state.finalResultBuilt) {
        _state.finalResultBuilt = true;
        yield await _buildFinalResult(event.response);
      }
      return;
    }

    if (event is openai.ResponseFailed) {
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

    // Handle special image generation events with attachment tracking
    if (event is openai.ResponseImageGenerationCallPartialImage) {
      _attachments.recordPartialImage(
        base64: event.partialImageB64,
        index: event.partialImageIndex,
      );
      yield* _toolRecorder.recordToolEventIfNeeded(event, _state);
      return;
    }

    if (event is openai.ResponseImageGenerationCallCompleted) {
      _attachments.markImageGenerationCompleted();
      yield* _toolRecorder.recordToolEventIfNeeded(event, _state);
      return;
    }

    // Handle code interpreter code deltas with accumulation
    if (event is openai.ResponseCodeInterpreterCallCodeDelta) {
      // Accumulate code deltas for message metadata
      final itemId = event.itemId;
      _state.getCodeInterpreterBuffer(itemId).write(event.delta);

      // Stream individual deltas as chunk metadata (like thinking)
      yield* _toolRecorder.yieldToolMetadataChunk(
        OpenAIResponsesToolTypes.codeInterpreter,
        event,
      );
      return;
    }

    if (event is openai.ResponseCodeInterpreterCallCodeDone) {
      // Emit a single accumulated code delta in message metadata
      final itemId = event.itemId;
      final buffer = _state.codeInterpreterCodeBuffers[itemId];
      final accumulatedCode = buffer?.toString();

      if (accumulatedCode != null) {
        // Record a single code_delta event with complete accumulated code
        // This goes into message metadata only (not streamed as chunk)
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

      // Record and yield the actual done event
      _toolRecorder.recordToolEvent(
        OpenAIResponsesToolTypes.codeInterpreter,
        event,
        _state,
      );
      yield* _toolRecorder.yieldToolMetadataChunk(
        OpenAIResponsesToolTypes.codeInterpreter,
        event,
      );
      return;
    }

    // Delegate all other tool events to the recorder
    yield* _toolRecorder.recordToolEventIfNeeded(event, _state);
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
