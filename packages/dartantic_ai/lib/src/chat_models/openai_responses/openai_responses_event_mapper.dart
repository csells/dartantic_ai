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
  final List<Map<String, Object?>> _thinkingDetails = [];

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
    'computer_use': <Map<String, Object?>>[],
    'local_shell': <Map<String, Object?>>[],
    'mcp': <Map<String, Object?>>[],
    'code_interpreter': <Map<String, Object?>>[],
  };

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
      return;
    }

    if (event is openai.ResponseReasoningSummaryPartAdded) {
      _thinkingDetails.add({'summary_part_added': event.part.toJson()});
      return;
    }

    if (event is openai.ResponseReasoningSummaryPartDone) {
      _thinkingDetails.add({'summary_part_done': event.part.toJson()});
      return;
    }

    if (event is openai.ResponseReasoningDelta) {
      _thinkingDetails.add({'reasoning_delta': event.delta});
      return;
    }

    if (event is openai.ResponseReasoningDone) {
      _thinkingDetails.add({'reasoning_done': event.text});
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

    _recordToolEventIfNeeded(event);
  }

  void _recordToolEventIfNeeded(openai.ResponseEvent event) {
    if (event is openai.ResponseImageGenerationCallPartialImage ||
        event is openai.ResponseImageGenerationCallInProgress ||
        event is openai.ResponseImageGenerationCallGenerating ||
        event is openai.ResponseImageGenerationCallCompleted) {
      _recordToolEvent('image_generation', event);
      return;
    }

    if (event is openai.ResponseWebSearchCallInProgress ||
        event is openai.ResponseWebSearchCallSearching ||
        event is openai.ResponseWebSearchCallCompleted) {
      _recordToolEvent('web_search', event);
      return;
    }

    if (event is openai.ResponseFileSearchCallInProgress ||
        event is openai.ResponseFileSearchCallSearching ||
        event is openai.ResponseFileSearchCallCompleted) {
      _recordToolEvent('file_search', event);
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
      return;
    }

    if (event is openai.ResponseCodeInterpreterCallCodeDelta ||
        event is openai.ResponseCodeInterpreterCallCodeDone ||
        event is openai.ResponseCodeInterpreterCallInProgress ||
        event is openai.ResponseCodeInterpreterCallCompleted ||
        event is openai.ResponseCodeInterpreterCallInterpreting) {
      _recordToolEvent('code_interpreter', event);
      return;
    }
  }

  void _recordToolEvent(String key, openai.ResponseEvent event) {
    final logEntry = event.toJson();
    _toolEventLog.putIfAbsent(key, () => []).add(logEntry);
  }

  ChatResult<ChatMessage> _buildFinalResult(openai.Response response) {
    final parts = <Part>[];
    final toolCallNames = <String, String>{};
    final telemetry = <String, Object?>{};

    for (final entry in _toolEventLog.entries) {
      if (entry.value.isNotEmpty) {
        telemetry['${entry.key}_events'] = entry.value;
      }
    }

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
        if (item.summary.isNotEmpty) {
          final summary = item.summary.map((s) => s.text).join('\n');
          _thinkingBuffer.write(summary);
        }
        continue;
      }

      if (item is openai.CodeInterpreterCall) {
        final codeInterpreterTelemetry = _ensureTelemetryMap(
          telemetry,
          'code_interpreter',
        );
        _appendCodeInterpreterCall(codeInterpreterTelemetry, item);
        continue;
      }

      if (item is openai.ImageGenerationCall) {
        final imageTelemetry = _ensureTelemetryMap(
          telemetry,
          'image_generation',
        );
        _appendImageCall(imageTelemetry, item, parts);
        continue;
      }

      if (item is openai.WebSearchCall) {
        final webTelemetry = _ensureTelemetryMap(telemetry, 'web_search');
        _appendSimpleCall(webTelemetry, item.id, item.status.toJson());
        continue;
      }

      if (item is openai.FileSearchCall) {
        final fileTelemetry = _ensureTelemetryMap(telemetry, 'file_search');
        _appendFileSearchCall(fileTelemetry, item);
        continue;
      }

      if (item is openai.LocalShellCall) {
        final shellTelemetry = _ensureTelemetryMap(telemetry, 'local_shell');
        _appendLocalShellCall(shellTelemetry, item);
        continue;
      }

      if (item is openai.LocalShellCallOutput) {
        final shellTelemetry = _ensureTelemetryMap(telemetry, 'local_shell');
        _appendLocalShellOutput(shellTelemetry, item);
        continue;
      }

      if (item is openai.ComputerCallOutput) {
        final computerTelemetry = _ensureTelemetryMap(
          telemetry,
          'computer_use',
        );
        _appendComputerUseOutput(computerTelemetry, item);
        continue;
      }

      if (item is openai.McpCall) {
        final mcpTelemetry = _ensureTelemetryMap(telemetry, 'mcp');
        _appendMcpEntry(mcpTelemetry, {
          'type': 'call',
          'id': item.id,
          'name': item.name,
          'arguments': item.argumentsJson,
          'server_label': item.serverLabel,
          if (item.output != null) 'output': item.output,
          if (item.error != null) 'error': item.error,
        });
        continue;
      }

      if (item is openai.McpListTools) {
        final mcpTelemetry = _ensureTelemetryMap(telemetry, 'mcp');
        _appendMcpEntry(mcpTelemetry, {
          'type': 'list_tools',
          'id': item.id,
          'server_label': item.serverLabel,
          'tools': item.tools
              .map((tool) => tool.toJson())
              .toList(growable: false),
          if (item.error != null) 'error': item.error,
        });
        continue;
      }

      if (item is openai.McpApprovalRequest) {
        final mcpTelemetry = _ensureTelemetryMap(telemetry, 'mcp');
        _appendMcpEntry(mcpTelemetry, {
          'type': 'approval_request',
          'id': item.id,
          'name': item.name,
          'arguments': item.arguments,
          'server_label': item.serverLabel,
        });
        continue;
      }

      if (item is openai.McpApprovalResponse) {
        final mcpTelemetry = _ensureTelemetryMap(telemetry, 'mcp');
        _appendMcpEntry(mcpTelemetry, {
          'type': 'approval_response',
          'id': item.id,
          'approval_request_id': item.approvalRequestId,
          'approve': item.approve,
          if (item.reason != null) 'reason': item.reason,
        });
        continue;
      }
    }

    final messageMetadata = <String, Object?>{
      if (_thinkingBuffer.isNotEmpty) 'thinking': _thinkingBuffer.toString(),
      if (_thinkingDetails.isNotEmpty) 'thinking_details': _thinkingDetails,
      if (telemetry.isNotEmpty) ...telemetry,
    };

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
      // Return a message with ONLY metadata (no text) to avoid duplication
      final metadataOnlyMessage = ChatMessage(
        role: ChatMessageRole.model,
        parts: const [], // Empty parts - text already streamed
        metadata: messageMetadata, // Include the session metadata
      );

      return ChatResult<ChatMessage>(
        id: response.id,
        output: metadataOnlyMessage, // Metadata-only message for accumulator
        // Empty messages array - orchestrator builds from accumulated chunks
        messages: const [],
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

  Map<String, Object?> _ensureTelemetryMap(
    Map<String, Object?> telemetry,
    String key,
  ) {
    final existing = telemetry[key];
    if (existing is Map<String, Object?>) return existing;
    final created = <String, Object?>{};
    telemetry[key] = created;
    return created;
  }

  void _appendCodeInterpreterCall(
    Map<String, Object?> telemetry,
    openai.CodeInterpreterCall call,
  ) {
    final calls =
        (telemetry['calls'] as List<Map<String, Object?>>?)?.toList() ??
        <Map<String, Object?>>[];
    calls.add({
      'id': call.id,
      'code': call.code,
      'status': call.status.toJson(),
      if (call.containerId != null) 'container_id': call.containerId,
      if (call.results != null)
        'results': call.results!
            .map((result) => result.toJson())
            .toList(growable: false),
    });
    telemetry['calls'] = calls;
  }

  void _appendImageCall(
    Map<String, Object?> telemetry,
    openai.ImageGenerationCall call,
    List<Part> parts,
  ) {
    final calls =
        (telemetry['calls'] as List<Map<String, Object?>>?)?.toList() ??
        <Map<String, Object?>>[];
    final callMetadata = <String, Object?>{
      'id': call.id,
      'status': call.status.toJson(),
    };

    final result = call.resultBase64;
    if (result != null) {
      try {
        final bytes = base64Decode(result);
        parts.add(DataPart(bytes, mimeType: 'image/png', name: 'image.png'));
        callMetadata['result'] = {'bytes': bytes.length};
      } on FormatException catch (_) {
        callMetadata['result'] = {'raw': result};
      }
    }

    calls.add(callMetadata);
    telemetry['calls'] = calls;
  }

  void _appendSimpleCall(
    Map<String, Object?> telemetry,
    String id,
    String status,
  ) {
    final calls =
        (telemetry['calls'] as List<Map<String, Object?>>?)?.toList() ??
        <Map<String, Object?>>[];
    calls.add({'id': id, 'status': status});
    telemetry['calls'] = calls;
  }

  void _appendFileSearchCall(
    Map<String, Object?> telemetry,
    openai.FileSearchCall call,
  ) {
    final calls =
        (telemetry['calls'] as List<Map<String, Object?>>?)?.toList() ??
        <Map<String, Object?>>[];
    calls.add({
      'id': call.id,
      'status': call.status.toJson(),
      'queries': call.queries,
      if (call.results != null)
        'results': call.results!
            .map((result) => result.toJson())
            .toList(growable: false),
    });
    telemetry['calls'] = calls;
  }

  void _appendLocalShellCall(
    Map<String, Object?> telemetry,
    openai.LocalShellCall call,
  ) {
    final calls =
        (telemetry['calls'] as List<Map<String, Object?>>?)?.toList() ??
        <Map<String, Object?>>[];
    calls.add({
      'id': call.id,
      'call_id': call.callId,
      'status': call.status.toJson(),
      'action': call.action.toJson(),
    });
    telemetry['calls'] = calls;
  }

  void _appendLocalShellOutput(
    Map<String, Object?> telemetry,
    openai.LocalShellCallOutput output,
  ) {
    final outputs =
        (telemetry['outputs'] as List<Map<String, Object?>>?)?.toList() ??
        <Map<String, Object?>>[];
    outputs.add({
      'call_id': output.callId,
      'output': output.output,
      if (output.status != null) 'status': output.status!.toJson(),
    });
    telemetry['outputs'] = outputs;
  }

  void _appendComputerUseOutput(
    Map<String, Object?> telemetry,
    openai.ComputerCallOutput output,
  ) {
    final outputs =
        (telemetry['outputs'] as List<Map<String, Object?>>?)?.toList() ??
        <Map<String, Object?>>[];
    outputs.add({
      'call_id': output.callId,
      'output': output.output.toJson(),
      if (output.status != null) 'status': output.status!.toJson(),
      if (output.acknowledgedSafetyChecks != null)
        'acknowledged_safety_checks': output.acknowledgedSafetyChecks!
            .map((check) => check.toJson())
            .toList(growable: false),
    });
    telemetry['outputs'] = outputs;
  }

  void _appendMcpEntry(
    Map<String, Object?> telemetry,
    Map<String, Object?> entry,
  ) {
    final entries =
        (telemetry['entries'] as List<Map<String, Object?>>?)?.toList() ??
        <Map<String, Object?>>[];
    entries.add(entry);
    telemetry['entries'] = entries;
  }

  static List<Part> _mapOutputMessage(List<openai.ResponseContent> content) {
    final parts = <Part>[];
    for (final entry in content) {
      if (entry is openai.OutputTextContent) {
        parts.add(TextPart(entry.text));
      } else if (entry is openai.RefusalContent) {
        parts.add(TextPart(entry.refusal));
      } else {
        parts.add(TextPart(jsonEncode(entry.toJson())));
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
