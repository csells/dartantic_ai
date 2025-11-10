import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../../agent/orchestrators/default_streaming_orchestrator.dart';
import '../../agent/orchestrators/streaming_orchestrator.dart';
import '../../agent/streaming_state.dart';

/// Orchestrator for Google's double agent typed output with tools pattern.
///
/// Google Gemini does not support using tools and typed output (outputSchema)
/// simultaneously in a single API call. This orchestrator works around this
/// limitation by running two sequential phases:
///
/// **Phase 1 - Tool Execution:**
/// - Sends messages with tools (no outputSchema)
/// - Suppresses text output (we only care about tool calls)
/// - Executes all tool calls and accumulates tool results
/// - Loops back to allow model to make additional tool calls if needed
/// - Continues until model returns with no tool calls
///
/// **Phase 2 - Structured Output:**
/// - Sends full conversation history with outputSchema (no tools)
/// - Returns the structured JSON output
///
/// This allows Google to support the same capability as Anthropic, just with
/// a different implementation strategy.
class GoogleDoubleAgentOrchestrator extends DefaultStreamingOrchestrator {
  static final _logger = Logger('dartantic.orchestrator.google-double-agent');

  @override
  String get providerHint => 'google-double-agent';

  /// Tracks which phase we're in (true = phase 1 tools, false = phase 2).
  /// Each orchestrator instance is created per request, so instance state
  /// is safe and isolated.
  bool _isPhase1 = true;

  @override
  void initialize(StreamingState state) {
    super.initialize(state);
    _isPhase1 = true;
  }

  @override
  bool allowTextStreaming(
    StreamingState state,
    ChatResult<ChatMessage> result,
  ) =>
      // Phase 1: Suppress text, we only care about tool calls
      // Phase 2: Allow text streaming (it's the structured JSON output)
      !_isPhase1;

  @override
  Future<void> beforeModelStream(
    StreamingState state,
    ChatModel<ChatModelOptions> model, {
    JsonSchema? outputSchema,
  }) async {
    final phase = _isPhase1 ? 'phase 1 (tools)' : 'phase 2 (typed output)';
    _logger.fine(
      'Google double agent orchestrator $phase '
      'with ${state.conversationHistory.length} history messages',
    );
  }

  @override
  Stream<StreamingIterationResult> processIteration(
    ChatModel<ChatModelOptions> model,
    StreamingState state, {
    JsonSchema? outputSchema,
  }) async* {
    if (_isPhase1) {
      // Phase 1: Run with tools, no outputSchema
      _logger.fine('Phase 1: Executing tool calls');

      state.resetForNewMessage();
      await beforeModelStream(state, model, outputSchema: null);

      // Stream model response with tools (no outputSchema)
      await for (final result in model.sendStream(
        List.unmodifiable(state.conversationHistory),
        outputSchema: null, // NO outputSchema in phase 1
      )) {
        yield* onModelChunk(result, state);
        state.accumulatedMessage = state.accumulator.accumulate(
          state.accumulatedMessage,
          selectMessageForAccumulation(result),
        );
        state.lastResult = result;
      }

      final consolidatedMessage = state.accumulator.consolidate(
        state.accumulatedMessage,
      );

      // Check for empty message
      final emptyHandler = handleEmptyMessage(consolidatedMessage, state);
      if (emptyHandler != null) {
        yield* emptyHandler;
        return;
      }

      // Extract and execute tool calls
      final toolCalls = extractToolCalls(consolidatedMessage);

      if (toolCalls.isEmpty) {
        // No tools called - skip to phase 2 to get structured output
        _logger.fine('Phase 1: No tool calls, transitioning to phase 2');

        // Don't add the message to history yet - we'll get structured output
        // Suppress any text from phase 1
        final textParts = consolidatedMessage.parts
            .whereType<TextPart>()
            .toList();
        if (textParts.isNotEmpty) {
          state.addSuppressedTextParts(textParts);
        }
        state.addSuppressedMetadata({...consolidatedMessage.metadata});

        // Transition to phase 2
        _isPhase1 = false;
        _logger.fine('Transitioning to phase 2');

        // Continue iteration (will call processIteration again for phase 2)
        yield StreamingIterationResult(
          output: '',
          messages: const [],
          shouldContinue: true,
          finishReason: state.lastResult.finishReason,
          metadata: const {},
          usage: state.lastResult.usage,
        );
        return;
      }

      // Add the model's message with tool calls to history
      state.addToHistory(consolidatedMessage);

      yield StreamingIterationResult(
        output: '',
        messages: [consolidatedMessage],
        shouldContinue: true,
        finishReason: state.lastResult.finishReason,
        metadata: const {},
        usage: null,
      );

      // Execute tools
      _logger.info('Executing ${toolCalls.length} tool calls');
      registerToolCalls(toolCalls, state);
      state.requestNextMessagePrefix();

      final executionResults = await executeToolBatch(state, toolCalls);
      final toolResultParts = executionResults
          .map((result) => result.resultPart)
          .toList();

      if (toolResultParts.isNotEmpty) {
        final toolResultMessage = ChatMessage(
          role: ChatMessageRole.user,
          parts: toolResultParts,
        );

        state.addToHistory(toolResultMessage);
        state.resetEmptyAfterToolsContinuation();

        yield StreamingIterationResult(
          output: '',
          messages: [toolResultMessage],
          shouldContinue: true,
          finishReason: state.lastResult.finishReason,
          metadata: const {},
          usage: state.lastResult.usage,
        );
      }

      // Stay in phase 1 to allow model to make more tool calls
      // The transition to phase 2 happens when model returns with no tool calls
      _logger.fine('Continuing in phase 1 for potential additional tool calls');

      // Continue iteration (will call processIteration again in phase 1)
      yield StreamingIterationResult(
        output: '',
        messages: const [],
        shouldContinue: true,
        finishReason: state.lastResult.finishReason,
        metadata: const {},
        usage: state.lastResult.usage,
      );
    } else {
      // Phase 2: Run with outputSchema, no tools
      _logger.fine('Phase 2: Getting structured output');

      state.resetForNewMessage();
      await beforeModelStream(state, model, outputSchema: outputSchema);

      // Stream model response with outputSchema (no tools)
      await for (final result in model.sendStream(
        List.unmodifiable(state.conversationHistory),
        outputSchema: outputSchema, // outputSchema in phase 2
      )) {
        yield* onModelChunk(result, state);
        state.accumulatedMessage = state.accumulator.accumulate(
          state.accumulatedMessage,
          selectMessageForAccumulation(result),
        );
        state.lastResult = result;
      }

      final consolidatedMessage = state.accumulator.consolidate(
        state.accumulatedMessage,
      );

      // Check for empty message
      final emptyHandler = handleEmptyMessage(consolidatedMessage, state);
      if (emptyHandler != null) {
        yield* emptyHandler;
        return;
      }

      // Create final message with suppressed metadata
      final mergedMetadata = <String, dynamic>{
        ...state.suppressedToolCallMetadata,
        if (state.suppressedTextParts.isNotEmpty)
          'suppressedText': state.suppressedTextParts.map((p) => p.text).join(),
      };

      final finalMessage = ChatMessage(
        role: ChatMessageRole.model,
        parts: consolidatedMessage.parts,
        metadata: mergedMetadata,
      );

      state.addToHistory(finalMessage);

      // This is the final structured output - no output text since
      // onModelChunk already streamed it
      yield StreamingIterationResult(
        output: '',
        messages: [finalMessage],
        shouldContinue: false, // Done after phase 2
        finishReason: state.lastResult.finishReason,
        metadata: state.lastResult.metadata,
        usage: state.lastResult.usage,
      );

      // Clear suppressed data after emission
      state.clearSuppressedData();
    }
  }
}
