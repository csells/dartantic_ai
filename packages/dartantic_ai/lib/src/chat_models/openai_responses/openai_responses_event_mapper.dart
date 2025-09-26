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

  /// Logger for streaming transformations.
  static final Logger log = Logger(
    'dartantic.chat.mappers.openai_responses.events',
  );

  /// Model name used for this stream.
  final String modelName;

  /// Whether session persistence is enabled for this request.
  final bool storeSession;

  /// Mapping information derived from the conversation history.
  final OpenAIResponsesHistorySegment history;

  final StringBuffer _thinkingBuffer = StringBuffer();
  final List<Map<String, Object?>> _thinkingDetails = [];

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
    if (event is openai.ResponseOutputTextDelta) {
      if (event.delta.isEmpty) return;
      final message = ChatMessage(
        role: ChatMessageRole.model,
        parts: [TextPart(event.delta)],
      );
      yield ChatResult(
        output: message,
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
      yield _buildFinalResult(event.response);
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

    for (final item in response.output ?? const <openai.ResponseItem>[]) {
      if (item is openai.OutputMessage) {
        parts.addAll(_mapOutputMessage(item.content));
        continue;
      }

      if (item is openai.FunctionCall) {
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
      OpenAIResponsesMetadata.setSessionData(
        messageMetadata,
        OpenAIResponsesMetadata.buildSession(
          previousResponseId: response.id,
          pending: const [],
        ),
      );
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

    return ChatResult(
      id: response.id,
      output: finalMessage,
      messages: [finalMessage],
      usage: usage,
      finishReason: _mapFinishReason(response),
      metadata: resultMetadata,
    );
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
