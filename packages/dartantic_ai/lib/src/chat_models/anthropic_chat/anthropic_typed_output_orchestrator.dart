import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../../agent/orchestrators/default_streaming_orchestrator.dart';
import '../../agent/orchestrators/streaming_orchestrator.dart';
import '../../agent/streaming_state.dart';
import '../../agent/tool_executor.dart';
import '../../providers/anthropic_provider.dart';

/// Orchestrator for Anthropic's typed output with return_result tool pattern.
///
/// Anthropic uses a special 'return_result' tool that the model calls with
/// structured JSON matching the output schema. This orchestrator handles:
/// - Detecting return_result tool calls
/// - Suppressing any text output (only JSON matters)
/// - Extracting and returning the structured result
class AnthropicTypedOutputOrchestrator extends DefaultStreamingOrchestrator {
  /// Creates an Anthropic typed output orchestrator.
  const AnthropicTypedOutputOrchestrator();

  static final _logger = Logger('dartantic.orchestrator.anthropic-typed');

  @override
  String get providerHint => 'anthropic-typed-output';

  @override
  bool allowTextStreaming(
    StreamingState state,
    ChatResult<ChatMessage> result,
  ) => false; // Never stream text, always wait for return_result

  @override
  Future<void> beforeModelStream(
    StreamingState state,
    ChatModel<ChatModelOptions> model, {
    JsonSchema? outputSchema,
  }) async {
    _logger.fine(
      'Anthropic typed output orchestrator starting '
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

      final toolCalls = extractToolCalls(consolidatedMessage);
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

      // Add the model message with tool calls to history so Claude sees the
      // pattern of using return_result for typed output.
      state.addToHistory(consolidatedMessage);

      yield* _executeReturnResultFlow(toolCalls, state, consolidatedMessage);
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
    ChatMessage modelMessage,
  ) async* {
    // Yield the model message with tool calls so the caller can accumulate it
    // for multi-turn conversations
    yield StreamingIterationResult(
      output: '',
      messages: [modelMessage],
      shouldContinue: true,
      finishReason: state.lastResult.finishReason,
      metadata: const {},
      usage: null,
    );

    registerToolCalls(toolCalls, state);
    state.requestNextMessagePrefix();

    final executionResults = await executeToolBatch(state, toolCalls);

    final otherResults = <ToolExecutionResult>[];
    ToolExecutionResult? returnResult;

    for (final result in executionResults) {
      if (result.toolPart.name ==
              AnthropicProvider.kAnthropicReturnResultTool &&
          result.isSuccess) {
        returnResult = result;
      } else {
        otherResults.add(result);
      }
    }

    // Build tool results for all tools including return_result
    // Anthropic requires every tool_use to have a corresponding tool_result
    final allResultParts = executionResults.map((r) => r.resultPart).toList();

    if (allResultParts.isNotEmpty) {
      final toolResultMessage = ChatMessage(
        role: ChatMessageRole.user,
        parts: allResultParts,
      );

      state.addToHistory(toolResultMessage);
      state.resetEmptyAfterToolsContinuation();

      // Yield all tool results (including return_result) so the caller's
      // history matches what Anthropic requires for subsequent turns
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

      // Don't yield a synthetic model message - that would teach Claude to
      // respond with plain text instead of using return_result.
      // The JSON output is available in result.output, and the tool interaction
      // pattern is preserved in the yielded model message with tool calls and
      // tool results.
      yield StreamingIterationResult(
        output: jsonOutput,
        messages: const [], // No synthetic message - preserve tool call pattern
        shouldContinue: false,
        finishReason: state.lastResult.finishReason,
        metadata: mergedMetadata,
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
          part.name == AnthropicProvider.kAnthropicReturnResultTool) {
        return part;
      }
    }
    return null;
  }
}
