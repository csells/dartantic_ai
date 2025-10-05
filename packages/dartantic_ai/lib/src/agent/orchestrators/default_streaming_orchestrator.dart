import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../streaming_state.dart';
import '../tool_executor.dart';
import 'streaming_orchestrator.dart';

/// Default implementation of the streaming orchestrator.
///
/// This class implements the standard agent streaming pattern and exposes
/// overridable hooks so specialised orchestrators can customise behaviour
/// without duplicating the control flow.
class DefaultStreamingOrchestrator implements StreamingOrchestrator {
  /// Creates a default streaming orchestrator.
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
  }

  @override
  Stream<StreamingIterationResult> processIteration(
    ChatModel<ChatModelOptions> model,
    StreamingState state, {
    JsonSchema? outputSchema,
  }) async* {
    state.resetForNewMessage();
    await beforeModelStream(state, model, outputSchema: outputSchema);

    await for (final result in model.sendStream(
      List.unmodifiable(state.conversationHistory),
      outputSchema: outputSchema,
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

    yield* onConsolidatedMessage(
      consolidatedMessage,
      state,
      model,
      outputSchema: outputSchema,
    );
  }

  /// Hook invoked before the model stream begins.
  @protected
  Future<void> beforeModelStream(
    StreamingState state,
    ChatModel<ChatModelOptions> model, {
    JsonSchema? outputSchema,
  }) async {}

  /// Handles a single streaming chunk from the model response.
  @protected
  Stream<StreamingIterationResult> onModelChunk(
    ChatResult<ChatMessage> result,
    StreamingState state,
  ) async* {
    final textOutput = _extractText(result);
    final hasMetadata = result.metadata.isNotEmpty;

    final streamText =
        textOutput.isNotEmpty && allowTextStreaming(state, result);
    if (!streamText && !hasMetadata) {
      return;
    }

    var streamOutput = '';
    if (streamText) {
      streamOutput = _shouldPrefixNewline(state) ? '\n$textOutput' : textOutput;
      state.markMessageStarted();
    }

    _logger.fine(
      'Streaming chunk: text=${streamOutput.length} chars, '
      'metadata=${result.metadata.keys}',
    );

    yield StreamingIterationResult(
      output: streamOutput,
      messages: const [],
      shouldContinue: true,
      finishReason: result.finishReason,
      metadata: result.metadata,
      usage: null, // Usage only in final result
    );
  }

  /// Whether this orchestrator should stream text chunks for the current
  /// result. Subclasses can override to suppress raw text streaming while still
  /// allowing metadata to flow.
  @protected
  bool allowTextStreaming(
    StreamingState state,
    ChatResult<ChatMessage> result,
  ) => true;

  /// Selects which message should be accumulated for the consolidated result.
  @protected
  ChatMessage selectMessageForAccumulation(ChatResult<ChatMessage> result) =>
      result.output.parts.isEmpty && result.messages.isNotEmpty
      ? result.messages.first
      : result.output;

  /// Handles the final consolidated message after the model stream completes.
  @protected
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

    state.addToHistory(consolidatedMessage);

    _logger.fine(
      'Orchestrator yielding consolidated message with metadata.keys='
      '${state.lastResult.metadata.keys}',
    );
    yield StreamingIterationResult(
      output: '',
      messages: [consolidatedMessage],
      shouldContinue: true,
      finishReason: state.lastResult.finishReason,
      metadata: state.lastResult.metadata,
      usage: null, // Usage only in final chunk
    );

    final toolCalls = _extractToolCalls(consolidatedMessage);
    if (toolCalls.isEmpty) {
      _logger.fine(
        'Orchestrator yielding final result (no tools) with metadata.keys='
        '${state.lastResult.metadata.keys}',
      );
      yield StreamingIterationResult(
        output: '',
        messages: const [],
        shouldContinue: false,
        finishReason: state.lastResult.finishReason,
        metadata: state.lastResult.metadata,
        usage: state.lastResult.usage, // Final usage here
      );
      return;
    }

    yield* executeToolCalls(toolCalls, state);
  }

  /// Handles empty assistant messages, optionally yielding results.
  @protected
  Stream<StreamingIterationResult>? handleEmptyMessage(
    ChatMessage message,
    StreamingState state,
  ) {
    if (message.parts.isEmpty) {
      if (hasRecentToolExecution(state)) {
        if (state.emptyAfterToolsContinuations < 1) {
          _logger.fine('Allowing one empty-after-tools continuation');
          state.noteEmptyAfterToolsContinuation();
          return Stream.value(
            StreamingIterationResult(
              output: '',
              messages: const [],
              shouldContinue: true,
              finishReason: state.lastResult.finishReason,
              metadata: state.lastResult.metadata,
              usage: state.lastResult.usage,
            ),
          );
        }

        _logger.fine(
          'Second empty-after-tools message encountered; treating as final',
        );
        state.addToHistory(message);
        return Stream.value(
          StreamingIterationResult(
            output: '',
            messages: [message],
            shouldContinue: false,
            finishReason: state.lastResult.finishReason,
            metadata: state.lastResult.metadata,
            usage: state.lastResult.usage,
          ),
        );
      }

      if (isLegitimateCompletion(state)) {
        _logger.fine('Empty message is legitimate completion, finishing');
        state.addToHistory(message);
        return Stream.value(
          StreamingIterationResult(
            output: '',
            messages: [message],
            shouldContinue: false,
            finishReason: state.lastResult.finishReason,
            metadata: state.lastResult.metadata,
            usage: state.lastResult.usage,
          ),
        );
      }
    }

    return null;
  }

  /// Executes tool calls and yields their results.
  @protected
  Stream<StreamingIterationResult> executeToolCalls(
    List<ToolPart> toolCalls,
    StreamingState state,
  ) async* {
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
        metadata: state.lastResult.metadata,
        usage: state.lastResult.usage,
      );
    }

    yield StreamingIterationResult(
      output: '',
      messages: const [],
      shouldContinue: true,
      finishReason: state.lastResult.finishReason,
      metadata: state.lastResult.metadata,
      usage: state.lastResult.usage,
    );
  }

  /// Executes the batch of tools via the shared tool executor.
  @protected
  Future<List<ToolExecutionResult>> executeToolBatch(
    StreamingState state,
    List<ToolPart> toolCalls,
  ) => state.executor.executeBatch(toolCalls, state.toolMap);

  /// Registers tool calls with the tool ID coordinator.
  @protected
  void registerToolCalls(List<ToolPart> toolCalls, StreamingState state) {
    for (final toolCall in toolCalls) {
      state.registerToolCall(
        id: toolCall.id,
        name: toolCall.name,
        arguments: toolCall.arguments,
      );
    }
  }

  /// Whether the conversation recently executed tools.
  @protected
  bool hasRecentToolExecution(StreamingState state) {
    if (state.conversationHistory.length < 2) {
      return false;
    }

    return state.conversationHistory
        .skip(state.conversationHistory.length - 2)
        .any(
          (message) => message.parts
              .whereType<ToolPart>()
              .where((p) => p.kind == ToolPartKind.result)
              .isNotEmpty,
        );
  }

  /// Whether the model's finish reason indicates a legitimate completion.
  @protected
  bool isLegitimateCompletion(StreamingState state) =>
      state.lastResult.finishReason == FinishReason.stop ||
      state.lastResult.finishReason == FinishReason.length;
}

String _extractText(ChatResult<ChatMessage> result) =>
    result.output.parts.whereType<TextPart>().map((p) => p.text).join();

bool _shouldPrefixNewline(StreamingState state) =>
    state.shouldPrefixNextMessage && state.isFirstChunkOfMessage;

List<ToolPart> _extractToolCalls(ChatMessage message) => message.parts
    .whereType<ToolPart>()
    .where((p) => p.kind == ToolPartKind.call)
    .toList();
