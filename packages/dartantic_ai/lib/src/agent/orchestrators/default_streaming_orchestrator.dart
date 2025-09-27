import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../streaming_state.dart';
import 'streaming_orchestrator.dart';

/// Default implementation of the streaming orchestrator
///
/// This implementation follows the standard agent streaming pattern:
/// 1. Stream model response
/// 2. Accumulate message parts
/// 3. Execute tool calls if present
/// 4. Continue until no more tool calls
class DefaultStreamingOrchestrator implements StreamingOrchestrator {
  /// Creates a default streaming orchestrator
  const DefaultStreamingOrchestrator();

  static final _logger = Logger('dartantic.orchestrator.default');

  @override
  String get providerHint => 'default';

  @override
  void initialize(StreamingState state) {
    _logger.fine('Initializing streaming orchestrator');
    state.resetForNewMessage();
  }

  @override
  void finalize(StreamingState state) {
    _logger.fine('Finalizing streaming orchestrator');
    // Default implementation doesn't need special cleanup
  }

  @override
  Stream<StreamingIterationResult> processIteration(
    ChatModel<ChatModelOptions> model,
    StreamingState state, {
    JsonSchema? outputSchema,
  }) async* {
    state.resetForNewMessage();

    // Stream the model response until the stream closes
    // Pass an immutable copy since we may modify state.conversationHistory
    // during processing (e.g., adding tool results)
    await for (final result in model.sendStream(
      List.unmodifiable(state.conversationHistory),
      outputSchema: outputSchema,
    )) {
      // Extract text content for streaming
      final textOutput = result.output.parts
          .whereType<TextPart>()
          .map((p) => p.text)
          .join();

      // Stream text if available
      if (textOutput.isNotEmpty) {
        _logger.fine('Streaming text chunk: ${textOutput.length} chars');

        // Handle newline prefixing for better UX
        final streamOutput = _shouldPrefixNewline(state)
            ? '\n$textOutput'
            : textOutput;

        state.markMessageStarted();

        yield StreamingIterationResult(
          output: streamOutput,
          messages: const [],
          shouldContinue: true,
          finishReason: result.finishReason,
          metadata: result.metadata,
          usage: result.usage,
        );
      }

      // Accumulate the message
      state.accumulatedMessage = state.accumulator.accumulate(
        state.accumulatedMessage,
        result.output,
      );
      state.lastResult = result;
    }

    // Now the stream has closed. Process the accumulated message.
    final consolidatedMessage = state.accumulator.consolidate(
      state.accumulatedMessage,
    );

    _logger.fine(
      'Stream closed. Consolidated message has '
      '${consolidatedMessage.parts.length} parts',
    );

    // Handle empty messages
    if (consolidatedMessage.parts.isEmpty) {
      _logger.fine('Empty message received');

      // Check if recent conversation involved tool execution
      // Look for tool result parts in the recent conversation history
      // If found, this empty message is likely Anthropic's response after
      // tool execution
      final recentToolExecution =
          state.conversationHistory.length >= 2 &&
          state.conversationHistory
              .skip(state.conversationHistory.length - 2)
              .any(
                (message) => message.parts
                    .whereType<ToolPart>()
                    .where((p) => p.kind == ToolPartKind.result)
                    .isNotEmpty,
              );

      // If this is immediately after tool execution, allow at most one
      // empty continuation, then treat subsequent empties as final to avoid
      // infinite looping with providers that intentionally return nothing
      if (recentToolExecution) {
        if (state.emptyAfterToolsContinuations < 1) {
          _logger.fine('Allowing one empty-after-tools continuation');
          state.noteEmptyAfterToolsContinuation();
          yield StreamingIterationResult(
            output: '',
            messages: const [],
            shouldContinue: true,
            finishReason: state.lastResult.finishReason,
            metadata: state.lastResult.metadata,
            usage: state.lastResult.usage,
          );
          return;
        }

        _logger.fine(
          'Second empty-after-tools message encountered; treating as final',
        );
        state.addToHistory(consolidatedMessage);

        yield StreamingIterationResult(
          output: '',
          messages: [consolidatedMessage],
          shouldContinue: false,
          finishReason: state.lastResult.finishReason,
          metadata: state.lastResult.metadata,
          usage: state.lastResult.usage,
        );
        return;
      }

      // Check if this is a legitimate completion (finish reason indicates done)
      final isLegitimateCompletion =
          state.lastResult.finishReason == FinishReason.stop ||
          state.lastResult.finishReason == FinishReason.length;

      if (isLegitimateCompletion) {
        // This is a real empty response (e.g., OpenAI returning empty
        // when asked without any prior tool execution)
        // Add it to history and complete
        _logger.fine('Empty message is legitimate completion, finishing');
        state.addToHistory(consolidatedMessage);

        yield StreamingIterationResult(
          output: '',
          messages: [consolidatedMessage],
          shouldContinue: false,
          finishReason: state.lastResult.finishReason,
          metadata: state.lastResult.metadata,
          usage: state.lastResult.usage,
        );
        return;
      }
    }

    // Add message to conversation history
    state.addToHistory(consolidatedMessage);

    // Yield the consolidated message
    yield StreamingIterationResult(
      output: '',
      messages: [consolidatedMessage],
      shouldContinue: true,
      finishReason: state.lastResult.finishReason,
      metadata: state.lastResult.metadata,
      usage: state.lastResult.usage,
    );

    // Check for tool calls
    final toolCalls = consolidatedMessage.parts
        .whereType<ToolPart>()
        .where((p) => p.kind == ToolPartKind.call)
        .toList();

    if (toolCalls.isEmpty) {
      // No tool calls - we're done
      _logger.fine('No tool calls found, iteration complete');
      yield StreamingIterationResult(
        output: '',
        messages: const [],
        shouldContinue: false,
        finishReason: state.lastResult.finishReason,
        metadata: state.lastResult.metadata,
        usage: state.lastResult.usage,
      );
      return;
    }

    // Execute tools and continue
    _logger.info('Executing ${toolCalls.length} tool calls');

    // Register tool calls
    for (final toolCall in toolCalls) {
      state.registerToolCall(
        id: toolCall.id,
        name: toolCall.name,
        arguments: toolCall.arguments,
      );
    }

    // Request newline prefix for next message
    state.requestNextMessagePrefix();

    // Execute all tools
    final executionResults = await state.executor.executeBatch(
      toolCalls,
      state.toolMap,
    );

    // Create tool result message
    final toolResultParts = executionResults
        .map((result) => result.resultPart)
        .toList();

    if (toolResultParts.isNotEmpty) {
      final toolResultMessage = ChatMessage(
        role: ChatMessageRole.user,
        parts: toolResultParts,
      );

      state.addToHistory(toolResultMessage);
      // Reset empty-after-tools guard for the next assistant turn
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

    // Continue processing
    yield StreamingIterationResult(
      output: '',
      messages: const [],
      shouldContinue: true,
      finishReason: state.lastResult.finishReason,
      metadata: state.lastResult.metadata,
      usage: state.lastResult.usage,
    );
  }

  bool _shouldPrefixNewline(StreamingState state) =>
      state.shouldPrefixNextMessage && state.isFirstChunkOfMessage;
}
