import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../streaming_state.dart';
import '../tool_constants.dart';
import 'default_streaming_orchestrator.dart';
import 'streaming_orchestrator.dart';

/// Orchestrator that handles typed output with return_result tool normalization
///
/// This orchestrator extends the default behavior to handle:
/// - return_result tool suppression for providers that use it
/// - JSON output streaming for native typed output providers
/// - Synthetic message creation for return_result responses
class TypedOutputStreamingOrchestrator extends DefaultStreamingOrchestrator {
  /// Creates a typed output streaming orchestrator
  const TypedOutputStreamingOrchestrator({
    required this.provider,
    required this.hasReturnResultTool,
  });

  /// The provider being used
  final Provider provider;

  /// Whether the model has return_result tool
  final bool hasReturnResultTool;

  static final _logger = Logger('dartantic.orchestrator.typed');

  @override
  String get providerHint => 'typed-output';

  @override
  Stream<StreamingIterationResult> processIteration(
    ChatModel<ChatModelOptions> model,
    StreamingState state, {
    JsonSchema? outputSchema,
  }) async* {
    state.resetForNewMessage();

    // Stream the model response
    await for (final result in model.sendStream(
      state.conversationHistory,
      outputSchema: outputSchema,
    )) {
      // Capture thinking metadata deltas (provider-agnostic) for this turn
      final thinkingMeta = result.metadata['thinking'];
      if (thinkingMeta is String && thinkingMeta.isNotEmpty) {
        state.thinkingBuffer.write(thinkingMeta);
      }
      // Check if we should stream native JSON text
      // Stream when:
      // 1. Provider doesn't have return_result in its tools (native support)
      // 2. Provider doesn't support typed output with tools at all
      if (!hasReturnResultTool) {
        final textOutput = result.output.parts
            .whereType<TextPart>()
            .map((p) => p.text)
            .join();

        if (textOutput.isNotEmpty) {
          _logger.fine(
            'Streaming native JSON text: ${textOutput.length} chars',
          );

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
      }
      // For return_result providers, don't stream any text during raw streaming
      // Text will only be streamed when we emit the synthetic JSON message

      // Accumulate the message
      state.accumulatedMessage = state.accumulator.accumulate(
        state.accumulatedMessage,
        result.output,
      );
      state.lastResult = result;
    }

    // Consolidate the accumulated message
    final consolidatedMessage = state.accumulator.consolidate(
      state.accumulatedMessage,
    );

    // Attach accumulated thinking to the consolidated model message metadata
    final consolidatedWithThinking = _attachThinkingToMessage(
      consolidatedMessage,
      state,
    );

    // Check if this message has return_result tool call
    final hasReturnResultCall = consolidatedMessage.parts
        .whereType<ToolPart>()
        .any(
          (p) => p.kind == ToolPartKind.call && p.name == kReturnResultToolName,
        );

    if (hasReturnResultCall) {
      // This is a return_result call - suppress it and save metadata/text
      final suppressedMeta = {...consolidatedWithThinking.metadata};
      // Ensure thinking moves forward into the synthetic message
      state.addSuppressedMetadata(suppressedMeta);
      final textParts = consolidatedMessage.parts
          .whereType<TextPart>()
          .toList();
      state.addSuppressedTextParts(textParts);
      _logger.fine('Suppressing return_result tool call message');
    } else if (provider.caps.contains(ProviderCaps.typedOutputWithTools) &&
        consolidatedMessage.parts.whereType<ToolPart>().isEmpty) {
      // For providers using return_result pattern, don't stream AI text
      // that comes before tool calls (it's usually explanatory)
      // Still yield the message but without text output
      yield StreamingIterationResult(
        output: '',
        messages: [consolidatedWithThinking],
        shouldContinue: true,
        finishReason: state.lastResult.finishReason,
        metadata: state.lastResult.metadata,
        usage: state.lastResult.usage,
      );
    } else {
      // Normal message for native typed output - yield it
      yield StreamingIterationResult(
        output: '',
        messages: [consolidatedWithThinking],
        shouldContinue: true,
        finishReason: state.lastResult.finishReason,
        metadata: state.lastResult.metadata,
        usage: state.lastResult.usage,
      );
    }

    // Only add non-empty messages to conversation history
    if (consolidatedMessage.parts.isNotEmpty) {
      state.addToHistory(consolidatedMessage);
    } else {
      _logger.fine('Skipping empty AI message in typed output');
    }

    // Check for tool calls
    final toolCalls = consolidatedMessage.parts
        .whereType<ToolPart>()
        .where((p) => p.kind == ToolPartKind.call)
        .toList();

    if (toolCalls.isEmpty) {
      _logger.fine('No tool calls found, completing iteration');
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

    // Execute tools
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

    // Separate return_result from other tools
    final toolResultParts = <Part>[];
    var returnResultJson = '';
    var returnResultMetadata = <String, dynamic>{};

    for (final result in executionResults) {
      if (result.toolPart.name == kReturnResultToolName && result.isSuccess) {
        // Extract the result content directly from the resultPart
        returnResultJson = result.resultPart.result ?? '';
        returnResultMetadata = {
          'toolId': result.toolPart.id,
          'toolName': result.toolPart.name,
        };
      } else {
        // Add other tool results to collection
        toolResultParts.add(result.resultPart);
      }
    }

    // Always add tool results to conversation history if we have any
    if (toolResultParts.isNotEmpty) {
      final toolResultMessage = ChatMessage(
        role: ChatMessageRole.user,
        parts: toolResultParts,
      );

      state.addToHistory(toolResultMessage);
      // Reset empty-after-tools guard for the next assistant turn to allow at
      // most one empty continuation without looping indefinitely.
      state.resetEmptyAfterToolsContinuation();

      // Only yield if not handling return_result normalization
      if (returnResultJson.isEmpty) {
        yield StreamingIterationResult(
          output: '',
          messages: [toolResultMessage],
          shouldContinue: true,
          finishReason: state.lastResult.finishReason,
          metadata: state.lastResult.metadata,
          usage: state.lastResult.usage,
        );
      }
    }

    // Handle return_result normalization
    if (returnResultJson.isNotEmpty) {
      // Create synthetic model message with JSON text
      final mergedMetadata = <String, dynamic>{
        ...state.suppressedToolCallMetadata,
        ...returnResultMetadata,
        // If any thinking remains, include it as part of the synthetic message
        if (state.thinkingBuffer.isNotEmpty)
          'thinking': state.thinkingBuffer.toString(),
        if (state.suppressedTextParts.isNotEmpty)
          'suppressedText': state.suppressedTextParts.map((p) => p.text).join(),
      };

      final syntheticMessage = ChatMessage(
        role: ChatMessageRole.model,
        parts: [TextPart(returnResultJson)],
        metadata: mergedMetadata,
      );

      _logger.fine('Yielding synthetic JSON message for return_result');

      // Yield the JSON as output and message (consistent with native providers)
      yield StreamingIterationResult(
        output: returnResultJson,
        messages: [syntheticMessage],
        shouldContinue: false, // return_result is always final
        finishReason: state.lastResult.finishReason,
        metadata: state.lastResult.metadata,
        usage: state.lastResult.usage,
      );

      // Clear suppressed data
      state.clearSuppressedData();
    } else {
      // Continue processing (more tool calls may follow)
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

  bool _shouldPrefixNewline(StreamingState state) =>
      state.shouldPrefixNextMessage && state.isFirstChunkOfMessage;

  /// Creates a copy of [message] with accumulated thinking (if any) attached
  /// to its metadata under key 'thinking'. The state's thinking buffer is not
  /// cleared here; it is cleared when the next message turn begins.
  ChatMessage _attachThinkingToMessage(
    ChatMessage message,
    StreamingState state,
  ) {
    if (state.thinkingBuffer.isEmpty) return message;
    final merged = <String, dynamic>{...message.metadata};
    final thinking = state.thinkingBuffer.toString();
    if (thinking.isNotEmpty) merged['thinking'] = thinking;
    return ChatMessage(
      role: message.role,
      parts: message.parts,
      metadata: merged,
    );
  }
}
