import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../streaming_state.dart';
import '../tool_constants.dart';
import '../tool_executor.dart';
import 'default_streaming_orchestrator.dart';
import 'streaming_orchestrator.dart';

/// Orchestrator that normalises typed output flows, including providers that
/// expose the `return_result` tool.
class TypedOutputStreamingOrchestrator extends DefaultStreamingOrchestrator {
  /// Creates a typed output streaming orchestrator.
  const TypedOutputStreamingOrchestrator({
    required this.provider,
    required this.hasReturnResultTool,
  });

  /// Provider being used for streaming.
  final Provider provider;

  /// Whether the model exposes the `return_result` tool.
  final bool hasReturnResultTool;

  static final _logger = Logger('dartantic.orchestrator.typed');

  @override
  String get providerHint => 'typed-output';

  @override
  bool allowTextStreaming(
    StreamingState state,
    ChatResult<ChatMessage> result,
  ) => !hasReturnResultTool;

  @override
  Future<void> beforeModelStream(
    StreamingState state,
    ChatModel<ChatModelOptions> model, {
    JsonSchema? outputSchema,
  }) async {
    _logger.fine(
      'Typed output orchestrator starting for provider ${provider.name} '
      'with ${state.conversationHistory.length} history messages',
    );
  }

  @override
  Stream<StreamingIterationResult> onConsolidatedMessage(
    ChatMessage consolidatedMessage,
    StreamingState state,
    ChatModel<ChatModelOptions> model, {
    JsonSchema? outputSchema,
  }) async* {
    final emptyHandler = handleEmptyMessage(consolidatedMessage, state);
    if (emptyHandler != null) {
      yield* emptyHandler;
      return;
    }

    final returnResultCall = _findReturnResultCall(consolidatedMessage);
    if (returnResultCall != null) {
      state.addSuppressedMetadata({...consolidatedMessage.metadata});
      final textParts = consolidatedMessage.parts
          .whereType<TextPart>()
          .toList();
      if (textParts.isNotEmpty) {
        state.addSuppressedTextParts(textParts);
      }

      final toolCalls = _extractToolCalls(consolidatedMessage);
      if (toolCalls.isEmpty) {
        _logger.warning(
          'return_result call detected but no tool parts found; '
          'terminating iteration early',
        );
        yield StreamingIterationResult(
          output: '',
          messages: const [],
          shouldContinue: false,
          finishReason: state.lastResult.finishReason,
          metadata: state.lastResult.metadata,
          usage: state.lastResult.usage,
        );
        state.clearSuppressedData();
        return;
      }

      yield* _executeReturnResultFlow(toolCalls, state);
      return;
    }

    // Fall back to default behaviour when no special handling is required.
    yield* super.onConsolidatedMessage(
      consolidatedMessage,
      state,
      model,
      outputSchema: outputSchema,
    );
  }

  Stream<StreamingIterationResult> _executeReturnResultFlow(
    List<ToolPart> toolCalls,
    StreamingState state,
  ) async* {
    registerToolCalls(toolCalls, state);
    state.requestNextMessagePrefix();

    final executionResults = await executeToolBatch(state, toolCalls);

    final otherResults = <ToolExecutionResult>[];
    ToolExecutionResult? returnResult;

    for (final result in executionResults) {
      if (result.toolPart.name == kReturnResultToolName && result.isSuccess) {
        returnResult = result;
      } else {
        otherResults.add(result);
      }
    }

    if (otherResults.isNotEmpty) {
      final toolResultMessage = ChatMessage(
        role: ChatMessageRole.user,
        parts: otherResults.map((r) => r.resultPart).toList(),
      );

      state.addToHistory(toolResultMessage);
      state.resetEmptyAfterToolsContinuation();

      yield StreamingIterationResult(
        output: '',
        messages: [toolResultMessage],
        shouldContinue: true,
        finishReason: state.lastResult.finishReason,
        metadata: state.lastResult.metadata,
        usage: state.lastResult.usage,
      );
    }

    if (returnResult != null) {
      final jsonOutput = returnResult.resultPart.result ?? '';
      final mergedMetadata = <String, dynamic>{
        ...state.suppressedToolCallMetadata,
        'toolId': returnResult.toolPart.id,
        'toolName': returnResult.toolPart.name,
        if (state.suppressedTextParts.isNotEmpty)
          'suppressedText': state.suppressedTextParts.map((p) => p.text).join(),
      };

      final syntheticMessage = ChatMessage(
        role: ChatMessageRole.model,
        parts: [TextPart(jsonOutput)],
        metadata: mergedMetadata,
      );

      yield StreamingIterationResult(
        output: jsonOutput,
        messages: [syntheticMessage],
        shouldContinue: false,
        finishReason: state.lastResult.finishReason,
        metadata: state.lastResult.metadata,
        usage: state.lastResult.usage,
      );

      state.clearSuppressedData();
    } else {
      // Allow the loop to continue if the return_result tool failed.
      yield StreamingIterationResult(
        output: '',
        messages: const [],
        shouldContinue: true,
        finishReason: state.lastResult.finishReason,
        metadata: state.lastResult.metadata,
        usage: state.lastResult.usage,
      );
    }
  }

  ToolPart? _findReturnResultCall(ChatMessage message) {
    for (final part in message.parts.whereType<ToolPart>()) {
      if (part.kind == ToolPartKind.call &&
          part.name == kReturnResultToolName) {
        return part;
      }
    }
    return null;
  }

  List<ToolPart> _extractToolCalls(ChatMessage message) => message.parts
      .whereType<ToolPart>()
      .where((p) => p.kind == ToolPartKind.call)
      .toList();
}
