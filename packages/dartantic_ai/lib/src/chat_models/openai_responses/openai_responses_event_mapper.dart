import 'dart:convert';
import 'dart:typed_data';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../../shared/openai_responses_metadata.dart';
import 'openai_responses_message_mapper.dart';

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
  }) : _attachments = _AttachmentCollector(
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
  final _AttachmentCollector _attachments;

  final StringBuffer _thinkingBuffer = StringBuffer();

  // Accumulate function calls during streaming
  // Key is outputIndex as string, value is the function call being built
  final Map<int, _StreamingFunctionCall> _functionCalls = {};

  // Track what we've already streamed to avoid duplication
  bool _hasStreamedText = false;
  final StringBuffer _streamedTextBuffer = StringBuffer();

  // Track whether we've already built the final result
  bool _finalResultBuilt = false;

  final Map<String, List<Map<String, Object?>>> _toolEventLog = {
    'web_search': <Map<String, Object?>>[],
    'file_search': <Map<String, Object?>>[],
    'image_generation': <Map<String, Object?>>[],
    'local_shell': <Map<String, Object?>>[],
    'mcp': <Map<String, Object?>>[],
    'code_interpreter': <Map<String, Object?>>[],
  };

  // Track which outputIndex contains reasoning text
  final Set<int> _reasoningOutputIndices = {};

  // Accumulate code interpreter code deltas
  // Key is item_id, value is the accumulated code string
  final Map<String, StringBuffer> _codeInterpreterCodeBuffers = {};

  /// Processes a streaming [event] and emits zero or more [ChatResult]s.
  Stream<ChatResult<ChatMessage>> handle(openai.ResponseEvent event) async* {
    // Handle function call item creation
    if (event is openai.ResponseOutputItemAdded) {
      final item = event.item;
      _logger.fine('ResponseOutputItemAdded: item type = ${item.runtimeType}');
      if (item is openai.FunctionCall) {
        // Store initial function call info indexed by outputIndex
        _functionCalls[event.outputIndex] = _StreamingFunctionCall(
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
        _reasoningOutputIndices.add(event.outputIndex);
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
        _recordToolEvent('code_interpreter', event);
        yield* _yieldToolMetadataChunk('code_interpreter', event);
      }

      return;
    }

    // Handle function call argument streaming
    if (event is openai.ResponseFunctionCallArgumentsDelta) {
      // Find the function call by outputIndex
      final call = _functionCalls[event.outputIndex];
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
      final call = _functionCalls[event.outputIndex];
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
      if (_reasoningOutputIndices.contains(event.outputIndex)) {
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
      _hasStreamedText = true;
      _streamedTextBuffer.write(event.delta);

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
      _thinkingBuffer.write(event.delta);
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
      if (!_finalResultBuilt) {
        _finalResultBuilt = true;
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

    yield* _recordToolEventIfNeeded(event);
  }

  Stream<ChatResult<ChatMessage>> _recordToolEventIfNeeded(
    openai.ResponseEvent event,
  ) async* {
    if (event is openai.ResponseImageGenerationCallPartialImage ||
        event is openai.ResponseImageGenerationCallInProgress ||
        event is openai.ResponseImageGenerationCallGenerating ||
        event is openai.ResponseImageGenerationCallCompleted) {
      _recordToolEvent('image_generation', event);

      // Track partial images as they arrive
      if (event is openai.ResponseImageGenerationCallPartialImage) {
        _attachments.recordPartialImage(
          base64: event.partialImageB64,
          index: event.partialImageIndex,
        );
      }

      if (event is openai.ResponseImageGenerationCallCompleted) {
        _attachments.markImageGenerationCompleted();
      }

      yield* _yieldToolMetadataChunk('image_generation', event);
      return;
    }

    if (event is openai.ResponseWebSearchCallInProgress ||
        event is openai.ResponseWebSearchCallSearching ||
        event is openai.ResponseWebSearchCallCompleted) {
      yield* _handleStandardToolEvent('web_search', event);
      return;
    }

    if (event is openai.ResponseFileSearchCallInProgress ||
        event is openai.ResponseFileSearchCallSearching ||
        event is openai.ResponseFileSearchCallCompleted) {
      yield* _handleStandardToolEvent('file_search', event);
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
      yield* _handleStandardToolEvent('mcp', event);
      return;
    }

    if (event is openai.ResponseCodeInterpreterCallCodeDelta) {
      // Accumulate code deltas for message metadata
      final itemId = event.itemId;
      _codeInterpreterCodeBuffers
          .putIfAbsent(itemId, StringBuffer.new)
          .write(event.delta);

      // Stream individual deltas as chunk metadata (like thinking)
      yield* _yieldToolMetadataChunk('code_interpreter', event);
      return;
    }

    if (event is openai.ResponseCodeInterpreterCallCodeDone) {
      // Emit a single accumulated code delta in message metadata
      final itemId = event.itemId;
      final accumulatedCode = _codeInterpreterCodeBuffers[itemId]?.toString();

      if (accumulatedCode != null) {
        // Record a single code_delta event with complete accumulated code
        // This goes into message metadata only (not streamed as chunk)
        final completeEvent = {
          'type': 'response.code_interpreter_call_code.delta',
          'item_id': itemId,
          'output_index': event.outputIndex,
          'delta': accumulatedCode,
        };

        _toolEventLog['code_interpreter']!.add(completeEvent);
      }
      _codeInterpreterCodeBuffers.remove(itemId);

      // Record and yield the actual done event
      _recordToolEvent('code_interpreter', event);
      yield* _yieldToolMetadataChunk('code_interpreter', event);
      return;
    }

    if (event is openai.ResponseCodeInterpreterCallInProgress ||
        event is openai.ResponseCodeInterpreterCallCompleted ||
        event is openai.ResponseCodeInterpreterCallInterpreting) {
      yield* _handleStandardToolEvent('code_interpreter', event);
      return;
    }
  }

  void _recordToolEvent(String key, openai.ResponseEvent event) {
    final logEntry = event.toJson();
    _toolEventLog.putIfAbsent(key, () => []).add(logEntry);
  }

  Stream<ChatResult<ChatMessage>> _yieldToolMetadataChunk(
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
      usage: const LanguageModelUsage(),
    );
  }

  /// Helper to record and yield tool events for standard tool types.
  Stream<ChatResult<ChatMessage>> _handleStandardToolEvent(
    String toolKey,
    openai.ResponseEvent event,
  ) async* {
    _recordToolEvent(toolKey, event);
    yield* _yieldToolMetadataChunk(toolKey, event);
  }

  /// Maps response items to dartantic Parts.
  ///
  /// Returns a record containing the mapped parts and a mapping of tool call
  /// IDs to their names (needed for mapping function outputs).
  ({List<Part> parts, Map<String, String> toolCallNames}) _mapResponseItems(
    List<openai.ResponseItem> items,
  ) {
    final parts = <Part>[];
    final toolCallNames = <String, String>{};

    _logger.info('Mapping ${items.length} response items');
    for (final item in items) {
      _logger.info('Processing response item: ${item.runtimeType}');
      if (item is openai.OutputMessage) {
        final messageParts = _mapOutputMessage(item.content);
        _logger.info(
          'OutputMessage has ${item.content.length} content items, '
          'mapped to ${messageParts.length} parts',
        );
        for (final part in messageParts) {
          if (part is TextPart) {
            _logger.info('Adding TextPart with text: "${part.text}"');
          }
        }
        parts.addAll(messageParts);
        continue;
      }

      if (item is openai.FunctionCall) {
        _logger.fine(
          'Adding function call to final result: ${item.name} '
          '(id=${item.callId})',
        );
        toolCallNames[item.callId] = item.name;
        parts.add(
          ToolPart.call(
            id: item.callId,
            name: item.name,
            arguments: _decodeArguments(item.arguments),
          ),
        );
        continue;
      }

      if (item is openai.FunctionCallOutput) {
        final toolName = toolCallNames[item.callId] ?? item.callId;
        parts.add(
          ToolPart.result(
            id: item.callId,
            name: toolName,
            result: _decodeResult(item.output),
          ),
        );
        continue;
      }

      if (item is openai.Reasoning) {
        // Already accumulated via ResponseReasoningSummaryTextDelta
        continue;
      }

      if (item is openai.CodeInterpreterCall) {
        // Events streamed in ChatResult.metadata
        continue;
      }

      if (item is openai.ImageGenerationCall) {
        _attachments.registerImageCall(item);
        continue;
      }

      if (item is openai.WebSearchCall || item is openai.FileSearchCall) {
        // Events streamed in ChatResult.metadata
        continue;
      }

      if (item is openai.LocalShellCall ||
          item is openai.LocalShellCallOutput ||
          item is openai.ComputerCallOutput ||
          item is openai.McpCall ||
          item is openai.McpListTools ||
          item is openai.McpApprovalRequest ||
          item is openai.McpApprovalResponse) {
        // Events streamed in ChatResult.metadata
        continue;
      }
    }

    return (parts: parts, toolCallNames: toolCallNames);
  }

  /// Builds session metadata for message persistence.
  Map<String, Object?> _buildSessionMetadata(openai.Response response) {
    final metadata = <String, Object?>{};
    if (storeSession) {
      _logger.info('━━━ Storing Session Metadata ━━━');
      _logger.info('Response ID being stored: ${response.id}');
      OpenAIResponsesMetadata.setSessionData(
        metadata,
        OpenAIResponsesMetadata.buildSession(responseId: response.id),
      );
      _logger.info('Session metadata saved to model message');
      _logger.info('');
    }
    return metadata;
  }

  /// Builds result metadata for ChatResult.
  Map<String, Object?> _buildResultMetadata(openai.Response response) => {
    'response_id': response.id,
    if (response.model != null) 'model': response.model!.toJson(),
    if (response.status != null) 'status': response.status,
  };

  /// Creates a ChatResult for streaming scenarios where text was streamed.
  ChatResult<ChatMessage> _createStreamingResult({
    required String responseId,
    required List<Part> parts,
    required Map<String, Object?> messageMetadata,
    required LanguageModelUsage usage,
    required FinishReason finishReason,
    required Map<String, Object?> resultMetadata,
  }) {
    final nonTextParts =
        parts.where((p) => p is! TextPart).toList(growable: false);

    final metadataOnlyOutput = ChatMessage(
      role: ChatMessageRole.model,
      parts: const [],
      metadata: messageMetadata,
    );

    final messages = nonTextParts.isNotEmpty
        ? [
            ChatMessage(
              role: ChatMessageRole.model,
              parts: nonTextParts,
              metadata: messageMetadata,
            ),
          ]
        : const <ChatMessage>[];

    return ChatResult<ChatMessage>(
      id: responseId,
      output: metadataOnlyOutput,
      messages: messages,
      usage: usage,
      finishReason: finishReason,
      metadata: resultMetadata,
    );
  }

  /// Creates a ChatResult for non-streaming scenarios (e.g., tool-only).
  ChatResult<ChatMessage> _createNonStreamingResult({
    required String responseId,
    required ChatMessage message,
    required LanguageModelUsage usage,
    required FinishReason finishReason,
    required Map<String, Object?> resultMetadata,
  }) =>
      ChatResult<ChatMessage>(
        id: responseId,
        output: message,
        messages: [message],
        usage: usage,
        finishReason: finishReason,
        metadata: resultMetadata,
      );

  Future<ChatResult<ChatMessage>> _buildFinalResult(
    openai.Response response,
  ) async {
    final mapped = _mapResponseItems(
      response.output ?? const <openai.ResponseItem>[],
    );
    final parts = [...mapped.parts];

    final messageMetadata = _buildSessionMetadata(response);

    final attachmentParts = await _attachments.resolveAttachments();
    if (attachmentParts.isNotEmpty) {
      parts.addAll(attachmentParts);
    }

    _logger.fine('Building final message with ${parts.length} parts');
    for (final part in parts) {
      _logger.fine('  Part: ${part.runtimeType}');
    }

    final usage = _mapUsage(response.usage);
    final resultMetadata = _buildResultMetadata(response);
    final finishReason = _mapFinishReason(response);
    final responseId = response.id ?? '';

    if (_hasStreamedText) {
      return _createStreamingResult(
        responseId: responseId,
        parts: parts,
        messageMetadata: messageMetadata,
        usage: usage,
        finishReason: finishReason,
        resultMetadata: resultMetadata,
      );
    } else {
      final finalMessage = ChatMessage(
        role: ChatMessageRole.model,
        parts: parts,
        metadata: messageMetadata,
      );
      return _createNonStreamingResult(
        responseId: responseId,
        message: finalMessage,
        usage: usage,
        finishReason: finishReason,
        resultMetadata: resultMetadata,
      );
    }
  }

  List<Part> _mapOutputMessage(List<openai.ResponseContent> content) {
    final parts = <Part>[];
    for (final entry in content) {
      _logger.info('Processing ResponseContent: ${entry.runtimeType}');
      if (entry is openai.OutputTextContent) {
        _logger.info('OutputTextContent text: "${entry.text}"');
        parts.add(TextPart(entry.text));

        // Extract container file citations from annotations
        for (final annotation in entry.annotations) {
          if (annotation is openai.ContainerFileCitation) {
            // Skip phantom citations where start_index == end_index
            if (annotation.startIndex == annotation.endIndex) {
              _logger.fine(
                'Skipping zero-length container file citation: '
                'file_id=${annotation.fileId}',
              );
              continue;
            }

            _logger.info(
              'Found container file citation: '
              'container_id=${annotation.containerId}, '
              'file_id=${annotation.fileId}',
            );

            // Track files for downloading as DataParts
            _attachments.trackContainerCitation(
              containerId: annotation.containerId,
              fileId: annotation.fileId,
            );
            _logger.info('Queued file for download: ${annotation.fileId}');
          }
        }
      } else if (entry is openai.RefusalContent) {
        parts.add(TextPart(entry.refusal));
      } else {
        final json = entry.toJson();
        _logger.info('OtherResponseContent: $json');
        // Check if this is reasoning content that shouldn't be in output
        if (json['type'] == 'reasoning_summary_text') {
          _logger.info(
            'Skipping reasoning_summary_text from output - '
            'already in thinking buffer',
          );
          // Skip - already accumulated via ResponseReasoningSummaryTextDelta
          continue;
        }
        parts.add(TextPart(jsonEncode(json)));
      }
    }
    return parts;
  }

  static Map<String, dynamic> _decodeArguments(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'value': decoded};
  }

  static dynamic _decodeResult(String raw) => jsonDecode(raw);

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

/// Helper class to accumulate function call arguments during streaming.
class _StreamingFunctionCall {
  _StreamingFunctionCall({
    required this.itemId,
    required this.callId,
    required this.name,
    required this.outputIndex,
  });

  final String itemId;
  final String callId;
  final String name;
  final int outputIndex;
  String arguments = '';

  void appendArguments(String delta) {
    arguments += delta;
  }

  bool get isComplete => arguments.isNotEmpty;
}

class _AttachmentCollector {
  _AttachmentCollector({
    required Logger logger,
    required ContainerFileLoader containerFileLoader,
  }) : _logger = logger,
       _containerFileLoader = containerFileLoader;

  final Logger _logger;
  final ContainerFileLoader _containerFileLoader;

  String? _latestImageBase64;
  int? _latestImageIndex;
  bool _imageGenerationCompleted = false;

  final Set<({String containerId, String fileId})> _containerFiles = {};

  void recordPartialImage({required String base64, required int index}) {
    _latestImageBase64 = base64;
    _latestImageIndex = index;
    _logger.fine('Stored partial image index: $_latestImageIndex');
  }

  void markImageGenerationCompleted({String? resultBase64}) {
    _imageGenerationCompleted = true;
    if (resultBase64 != null && resultBase64.isNotEmpty) {
      _latestImageBase64 = resultBase64;
    }
  }

  void registerImageCall(openai.ImageGenerationCall call) {
    markImageGenerationCompleted(resultBase64: call.resultBase64);
  }

  void trackContainerCitation({
    required String containerId,
    required String fileId,
  }) {
    _containerFiles.add((containerId: containerId, fileId: fileId));
  }

  Future<List<DataPart>> resolveAttachments() async {
    final attachments = <DataPart>[];
    final imageParts = _resolveImageAttachments();
    if (imageParts != null) {
      attachments.add(imageParts);
    }

    if (_containerFiles.isNotEmpty) {
      attachments.addAll(await _resolveContainerAttachments());
    }

    return attachments;
  }

  DataPart? _resolveImageAttachments() {
    if (!_imageGenerationCompleted || _latestImageBase64 == null) {
      return null;
    }

    final decodedBytes = Uint8List.fromList(base64Decode(_latestImageBase64!));
    // Use lookupMimeType with headerBytes to detect MIME type from file signature
    final inferredMime =
        lookupMimeType('image.bin', headerBytes: decodedBytes) ??
        'application/octet-stream';
    final extension = Part.extensionFromMimeType(inferredMime);
    final baseName = 'image_${_latestImageIndex ?? 0}';

    // Build filename with extension if available (extension lacks dot prefix)
    final imageName = extension != null ? '$baseName.$extension' : baseName;

    return DataPart(decodedBytes, mimeType: inferredMime, name: imageName);
  }

  Future<List<DataPart>> _resolveContainerAttachments() async {
    final attachments = <DataPart>[];

    for (final citation in _containerFiles) {
      final containerId = citation.containerId;
      final fileId = citation.fileId;
      _logger.info('Downloading container file: $fileId from $containerId');
      final data = await _containerFileLoader(containerId, fileId);

      final inferredMime =
          data.mimeType ??
          lookupMimeType(
            data.fileName ?? '',
            headerBytes: data.bytes,
          ) ??
          'application/octet-stream';
      final extension = Part.extensionFromMimeType(inferredMime);
      final fileName =
          data.fileName ??
          (extension != null ? '$fileId.$extension' : fileId);

      attachments.add(
        DataPart(data.bytes, mimeType: inferredMime, name: fileName),
      );
      _logger.info(
        'Added container file as DataPart '
        '(${data.bytes.length} bytes, mime: $inferredMime)',
      );
    }

    _containerFiles.clear();
    return attachments;
  }
}
