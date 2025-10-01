import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../../shared/openai_responses_metadata.dart';
import 'openai_responses_message_mapper.dart';

/// Maps OpenAI Responses streaming events into dartantic chat results.
class OpenAIResponsesEventMapper {
  /// Creates a new mapper configured for a specific stream invocation.
  OpenAIResponsesEventMapper({
    required this.modelName,
    required this.storeSession,
    required this.history,
  });

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses.event_mapper',
  );

  /// Model name used for this stream.
  final String modelName;

  /// Whether session persistence is enabled for this request.
  final bool storeSession;

  /// Mapping information derived from the conversation history.
  final OpenAIResponsesHistorySegment history;

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

  // Track the last partial image for adding to final result
  String? _lastPartialImageB64;
  int? _lastPartialImageIndex;

  // Accumulate code interpreter code deltas
  // Key is item_id, value is the accumulated code string
  final Map<String, StringBuffer> _codeInterpreterCodeBuffers = {};
  bool _imageGenerationCompleted = false;

  /// Processes a streaming [event] and emits zero or more [ChatResult]s.
  Iterable<ChatResult<ChatMessage>> handle(openai.ResponseEvent event) sync* {
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
        // Mark that image generation is done - the last partial image is final
        _imageGenerationCompleted = true;
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
        yield _buildFinalResult(event.response);
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

  Iterable<ChatResult<ChatMessage>> _recordToolEventIfNeeded(
    openai.ResponseEvent event,
  ) sync* {
    if (event is openai.ResponseImageGenerationCallPartialImage ||
        event is openai.ResponseImageGenerationCallInProgress ||
        event is openai.ResponseImageGenerationCallGenerating ||
        event is openai.ResponseImageGenerationCallCompleted) {
      _recordToolEvent('image_generation', event);

      // Track partial images as they arrive
      if (event is openai.ResponseImageGenerationCallPartialImage) {
        _lastPartialImageB64 = event.partialImageB64;
        _lastPartialImageIndex = event.partialImageIndex;
        _logger.fine('Stored partial image index: $_lastPartialImageIndex');
      }

      // Note: ResponseImageGenerationCallCompleted is defined in openai_core
      // but OpenAI never actually sends it. Image generation completion is
      // signaled by ResponseOutputItemDone with an ImageGenerationCall item.
      if (event is openai.ResponseImageGenerationCallCompleted) {
        _logger.warning(
          'Received unexpected ResponseImageGenerationCallCompleted event',
        );
        _imageGenerationCompleted = true;
      }

      yield* _yieldToolMetadataChunk('image_generation', event);
      return;
    }

    if (event is openai.ResponseWebSearchCallInProgress ||
        event is openai.ResponseWebSearchCallSearching ||
        event is openai.ResponseWebSearchCallCompleted) {
      _recordToolEvent('web_search', event);
      yield* _yieldToolMetadataChunk('web_search', event);
      return;
    }

    if (event is openai.ResponseFileSearchCallInProgress ||
        event is openai.ResponseFileSearchCallSearching ||
        event is openai.ResponseFileSearchCallCompleted) {
      _recordToolEvent('file_search', event);
      yield* _yieldToolMetadataChunk('file_search', event);
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
      _recordToolEvent('mcp', event);
      yield* _yieldToolMetadataChunk('mcp', event);
      return;
    }

    if (event is openai.ResponseCodeInterpreterCallCodeDelta) {
      // Accumulate code deltas instead of recording each one
      final itemId = event.itemId;
      _codeInterpreterCodeBuffers.putIfAbsent(itemId, StringBuffer.new)
        ..write(event.delta);
      // Don't yield individual deltas
      return;
    }

    if (event is openai.ResponseCodeInterpreterCallCodeDone) {
      // Emit a single code delta event with the complete accumulated code
      final itemId = event.itemId;
      final accumulatedCode = _codeInterpreterCodeBuffers[itemId]?.toString();

      // Record a single code_delta event with complete code
      final completeEvent = {
        'type': 'response.code_interpreter_call_code.delta',
        'item_id': itemId,
        'output_index': event.outputIndex,
        'delta': accumulatedCode ?? event.code,
      };

      _toolEventLog['code_interpreter']!.add(completeEvent);
      yield* _yieldToolMetadataChunk('code_interpreter', completeEvent);
      _codeInterpreterCodeBuffers.remove(itemId);

      // Now record and yield the actual done event
      _recordToolEvent('code_interpreter', event);
      yield* _yieldToolMetadataChunk('code_interpreter', event);
      return;
    }

    if (event is openai.ResponseCodeInterpreterCallInProgress ||
        event is openai.ResponseCodeInterpreterCallCompleted ||
        event is openai.ResponseCodeInterpreterCallInterpreting) {
      _recordToolEvent('code_interpreter', event);
      yield* _yieldToolMetadataChunk('code_interpreter', event);
      return;
    }
  }

  void _recordToolEvent(String key, openai.ResponseEvent event) {
    final logEntry = event.toJson();
    _toolEventLog.putIfAbsent(key, () => []).add(logEntry);
  }

  Iterable<ChatResult<ChatMessage>> _yieldToolMetadataChunk(
    String toolKey,
    Object eventOrMap,
  ) sync* {
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

  ChatResult<ChatMessage> _buildFinalResult(openai.Response response) {
    final parts = <Part>[];
    final toolCallNames = <String, String>{};

    // Start with accumulated event logs (will add synthetic events below)
    final messageMetadata = <String, Object?>{
      if (_thinkingBuffer.isNotEmpty) 'thinking': _thinkingBuffer.toString(),
      // Copy all non-empty tool event lists to message metadata
      for (final entry in _toolEventLog.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };

    _logger.info(
      'Building final result, response.output has '
      '${response.output?.length ?? 0} items',
    );
    for (final item in response.output ?? const <openai.ResponseItem>[]) {
      _logger.info('Processing response item: ${item.runtimeType}');
      if (item is openai.OutputMessage) {
        // Always process the output message to get the complete text
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
        // Don't add summary to buffer here - it's already been accumulated
        // via ResponseReasoningSummaryTextDelta events during streaming
        // Just skip this item
        continue;
      }

      // CodeInterpreter has additional data (code, results, containerId)
      // Add as synthetic summary event
      if (item is openai.CodeInterpreterCall) {
        final codeInterpreterEvents =
            messageMetadata['code_interpreter'] as List<Map<String, Object?>>?;
        codeInterpreterEvents?.add({
          'type': 'code_interpreter_call',
          'id': item.id,
          'code': item.code,
          if (item.results != null)
            'results': item.results!
                .map((r) => r.toJson())
                .toList(growable: false),
          if (item.containerId != null) 'container_id': item.containerId,
          'status': item.status.toJson(),
        });
        continue;
      }

      // ImageGenerationCall has no additional data beyond streaming events
      // The final image is already added as DataPart - ignore this item
      if (item is openai.ImageGenerationCall) {
        continue;
      }

      // WebSearchCall has no additional data beyond streaming events - ignore
      if (item is openai.WebSearchCall) {
        continue;
      }

      // FileSearch has additional data (queries, results)
      // Add as synthetic summary event
      if (item is openai.FileSearchCall) {
        final fileSearchEvents =
            messageMetadata['file_search'] as List<Map<String, Object?>>?;
        fileSearchEvents?.add({
          'type': 'file_search_call',
          'id': item.id,
          'queries': item.queries,
          if (item.results != null)
            'results': item.results!
                .map((r) => r.toJson())
                .toList(growable: false),
          'status': item.status.toJson(),
        });
        continue;
      }

      // LocalShell, ComputerUse, MCP - no additional data beyond streaming
      // events Ignore these items
      if (item is openai.LocalShellCall ||
          item is openai.LocalShellCallOutput ||
          item is openai.ComputerCallOutput ||
          item is openai.McpCall ||
          item is openai.McpListTools ||
          item is openai.McpApprovalRequest ||
          item is openai.McpApprovalResponse) {
        continue;
      }
    }

    if (storeSession) {
      _logger.info('━━━ Storing Session Metadata ━━━');
      _logger.info('Response ID being stored: ${response.id}');
      OpenAIResponsesMetadata.setSessionData(
        messageMetadata,
        OpenAIResponsesMetadata.buildSession(
          responseId: response.id, // Store THIS response's ID
        ),
      );
      _logger.info('Session metadata saved to model message');
      _logger.info('');
    }

    // Add the last partial image as a DataPart if image generation completed.
    // OpenAI signals completion via ResponseOutputItemDone (not the
    // ResponseImageGenerationCallCompleted event which is never sent).
    // The last partial image received IS the final image.
    if (_imageGenerationCompleted && _lastPartialImageB64 != null) {
      try {
        final bytes = base64Decode(_lastPartialImageB64!);
        parts.add(
          DataPart(
            bytes,
            mimeType: 'image/png',
            name: 'image_$_lastPartialImageIndex.png',
          ),
        );
        _logger.fine('Added final image as DataPart (${bytes.length} bytes)');
      } on FormatException catch (e) {
        _logger.warning('Failed to decode final image base64: $e');
      }
    }

    _logger.fine('Building final message with ${parts.length} parts');
    for (final part in parts) {
      _logger.fine('  Part: ${part.runtimeType}');
    }

    final finalMessage = ChatMessage(
      role: ChatMessageRole.model,
      parts: parts,
      metadata: messageMetadata,
    );

    final usage = _mapUsage(response.usage);
    final resultMetadata = <String, Object?>{
      'response_id': response.id,
      if (response.model != null) 'model': response.model!.toJson(),
      if (response.status != null) 'status': response.status,
    };

    // Per Message-Handling-Architecture.md:
    // Each ChatResult contains only NEW content from that specific chunk
    // When we've streamed text, we've already sent it in chunks
    // The final result should contain the complete message in messages array
    // but empty output to avoid duplication

    if (_hasStreamedText) {
      // We've already streamed the text content
      // The orchestrator will consolidate the accumulated chunks
      // Return metadata and any non-text parts (like images) in messages only
      final nonTextParts = parts
          .where((p) => p is! TextPart)
          .toList(growable: false);

      // Empty output to avoid duplication with streamed text
      final metadataOnlyOutput = ChatMessage(
        role: ChatMessageRole.model,
        parts: const [], // No parts in output - text already streamed
        metadata: messageMetadata, // Include metadata for orchestrator
      );

      // If there are non-text parts, include them in messages
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
        id: response.id,
        output: metadataOnlyOutput, // Empty parts, just metadata
        messages: messages, // Non-text parts here to avoid duplication
        usage: usage,
        finishReason: _mapFinishReason(response),
        metadata: resultMetadata,
      );
    } else {
      // No streaming occurred (e.g., tool-only response)
      // Include message in both output and messages
      return ChatResult<ChatMessage>(
        id: response.id,
        output: finalMessage,
        messages: [finalMessage],
        usage: usage,
        finishReason: _mapFinishReason(response),
        metadata: resultMetadata,
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
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {'value': decoded};
    } on FormatException catch (_) {
      return {'value': raw};
    }
  }

  static dynamic _decodeResult(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException catch (_) {
      return raw;
    }
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
