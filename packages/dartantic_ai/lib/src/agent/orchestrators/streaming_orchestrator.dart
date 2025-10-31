import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';

import '../streaming_state.dart';

/// Result from a single streaming iteration
class StreamingIterationResult {
  /// Creates a streaming iteration result
  const StreamingIterationResult({
    required this.output,
    required this.messages,
    required this.shouldContinue,
    required this.finishReason,
    this.metadata = const {},
    this.thinking,
    this.usage,
  });

  /// Text output to stream to the user
  final String output;

  /// Messages to yield (if any)
  final List<ChatMessage> messages;

  /// Whether to continue the streaming loop
  final bool shouldContinue;

  /// The finish reason from the model
  final FinishReason finishReason;

  /// Metadata from the iteration
  final Map<String, dynamic> metadata;

  /// Extended thinking content
  final String? thinking;

  /// Usage information
  final LanguageModelUsage? usage;
}

/// Orchestrates the streaming process, coordinating between model calls,
/// tool execution, and message accumulation
abstract class StreamingOrchestrator {
  /// Processes a single iteration of the streaming loop
  ///
  /// This method:
  /// 1. Calls the model with current conversation history
  /// 2. Accumulates and consolidates the response
  /// 3. Executes any tool calls
  /// 4. Updates conversation history
  /// 5. Determines if streaming should continue
  ///
  /// Returns a stream of iteration results that can be yielded to the caller
  Stream<StreamingIterationResult> processIteration(
    ChatModel<ChatModelOptions> model,
    StreamingState state, {
    JsonSchema? outputSchema,
  });

  /// Handles the initial setup before streaming begins
  void initialize(StreamingState state);

  /// Handles cleanup after streaming completes
  void finalize(StreamingState state);

  /// Provider hint for logging or debugging
  String get providerHint;
}
