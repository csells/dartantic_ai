import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

import '../chat_models/helpers/tool_id_helpers.dart';
import 'message_accumulator.dart';
import 'tool_executor.dart';

/// Encapsulates all mutable state required during streaming operations
class StreamingState {
  /// Creates a new StreamingState instance
  StreamingState({required this.conversationHistory, required this.toolMap});

  /// Logger for state.streaming operations.
  static final Logger _logger = Logger('dartantic.state.streaming');

  /// The conversation history being built up during streaming
  final List<ChatMessage> conversationHistory;

  /// Map of available tools by name
  final Map<String, Tool> toolMap;

  /// Message accumulator for provider-specific streaming logic
  final MessageAccumulator accumulator = const MessageAccumulator();

  /// Tool executor for provider-specific tool execution
  final ToolExecutor executor = const ToolExecutor();

  /// Coordinator for managing tool IDs across the conversation
  final ToolIdCoordinator toolIdCoordinator = ToolIdCoordinator();

  /// Whether we're done processing the stream
  bool done = false;

  /// Whether to prefix the next message with a newline for better UX
  bool shouldPrefixNextMessage = false;

  /// Whether this is the first chunk of the current message
  bool isFirstChunkOfMessage = true;

  /// The message being accumulated during streaming
  ChatMessage accumulatedMessage = const ChatMessage(
    role: ChatMessageRole.model,
    parts: [],
  );

  /// The last result received from the model
  ChatResult<ChatMessage> lastResult = ChatResult<ChatMessage>(
    output: const ChatMessage(role: ChatMessageRole.model, parts: []),
    finishReason: FinishReason.unspecified,
    metadata: const <String, dynamic>{},
    usage: const LanguageModelUsage(),
  );

  /// For typed output: metadata from suppressed tool calls
  Map<String, dynamic> suppressedToolCallMetadata = <String, dynamic>{};

  /// For typed output: text parts that were suppressed
  List<TextPart> suppressedTextParts = <TextPart>[];

  /// Count of consecutive empty assistant messages immediately after tool
  /// execution. Used to allow at most one "empty-after-tools" continuation
  /// to accommodate provider quirks, then stop to avoid infinite loops.
  int emptyAfterToolsContinuations = 0;

  /// Resets state for a new message in the conversation
  void resetForNewMessage() {
    _logger.fine('Resetting streaming state for new message');
    isFirstChunkOfMessage = true;
    accumulatedMessage = const ChatMessage(
      role: ChatMessageRole.model,
      parts: [],
    );
    lastResult = ChatResult<ChatMessage>(
      output: const ChatMessage(role: ChatMessageRole.model, parts: []),
      finishReason: FinishReason.unspecified,
      metadata: const <String, dynamic>{},
      usage: const LanguageModelUsage(),
    );
  }

  /// Marks that we've started streaming content for the current message
  void markMessageStarted() {
    isFirstChunkOfMessage = false;
  }

  /// Sets the flag to prefix the next message (after tool calls)
  void requestNextMessagePrefix() {
    _logger.fine('Setting newline prefix flag for next AI message');
    shouldPrefixNextMessage = true;
  }

  /// Completes the stream processing
  void complete() {
    done = true;
  }

  /// Adds a message to the conversation history
  void addToHistory(ChatMessage message) {
    conversationHistory.add(message);
  }

  /// Resets the empty-after-tools continuation counter (typically called when
  /// adding tool results to history so the next empty can be treated as
  /// intermediate once).
  void resetEmptyAfterToolsContinuation() {
    emptyAfterToolsContinuations = 0;
  }

  /// Records an observed empty message after tool execution.
  void noteEmptyAfterToolsContinuation() {
    emptyAfterToolsContinuations++;
  }

  /// For typed output: stores metadata from a suppressed tool call
  void addSuppressedMetadata(Map<String, dynamic> metadata) {
    suppressedToolCallMetadata.addAll(metadata);
  }

  /// For typed output: adds suppressed text parts
  void addSuppressedTextParts(List<TextPart> parts) {
    suppressedTextParts.addAll(parts);
  }

  /// For typed output: clears suppressed data after emission
  void clearSuppressedData() {
    _logger.fine('Clearing message chunk tracking state');
    suppressedToolCallMetadata = <String, dynamic>{};
    suppressedTextParts = <TextPart>[];
  }

  /// Resets the tool ID coordinator for a new conversation
  void resetToolIdCoordinator() {
    toolIdCoordinator.clear();
  }

  /// Registers a tool call with the coordinator
  void registerToolCall({
    required String id,
    required String name,
    Map<String, dynamic>? arguments,
  }) {
    toolIdCoordinator.registerToolCall(
      id: id,
      name: name,
      arguments: arguments,
    );
  }

  /// Validates that a tool result ID matches a registered tool call
  bool validateToolResultId(String id) =>
      toolIdCoordinator.validateToolResultId(id);
}
