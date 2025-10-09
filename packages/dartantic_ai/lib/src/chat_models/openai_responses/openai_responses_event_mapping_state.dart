import 'openai_responses_tool_types.dart';

/// Encapsulates all mutable state during OpenAI Responses event mapping.
class EventMappingState {
  /// Creates a new event mapping state instance.
  EventMappingState();

  /// Buffer for accumulating thinking/reasoning text.
  final StringBuffer thinkingBuffer = StringBuffer();

  /// Map of streaming function calls indexed by output index.
  final Map<int, StreamingFunctionCall> functionCalls = {};

  /// Whether any text has been streamed to the user.
  bool hasStreamedText = false;

  /// Buffer for accumulating streamed text.
  final StringBuffer streamedTextBuffer = StringBuffer();

  /// Whether the final result has been built and yielded.
  bool finalResultBuilt = false;

  /// Log of tool events organized by tool type.
  final Map<String, List<Map<String, Object?>>> toolEventLog = {
    OpenAIResponsesToolTypes.webSearch: <Map<String, Object?>>[],
    OpenAIResponsesToolTypes.fileSearch: <Map<String, Object?>>[],
    OpenAIResponsesToolTypes.imageGeneration: <Map<String, Object?>>[],
    OpenAIResponsesToolTypes.localShell: <Map<String, Object?>>[],
    OpenAIResponsesToolTypes.mcp: <Map<String, Object?>>[],
    OpenAIResponsesToolTypes.codeInterpreter: <Map<String, Object?>>[],
  };

  /// Set of output indices that contain reasoning text.
  final Set<int> reasoningOutputIndices = {};

  /// Buffers for accumulating code interpreter code deltas, keyed by item ID.
  final Map<String, StringBuffer> codeInterpreterCodeBuffers = {};

  /// Records a tool event in the log.
  void recordToolEvent(String toolType, Map<String, Object?> event) {
    toolEventLog.putIfAbsent(toolType, () => []).add(event);
  }

  /// Gets a code interpreter buffer for the given item ID, creating if needed.
  StringBuffer getCodeInterpreterBuffer(String itemId) =>
      codeInterpreterCodeBuffers.putIfAbsent(itemId, StringBuffer.new);

  /// Removes a code interpreter buffer for the given item ID.
  void removeCodeInterpreterBuffer(String itemId) {
    codeInterpreterCodeBuffers.remove(itemId);
  }
}

/// Helper class to accumulate function call arguments during streaming.
class StreamingFunctionCall {
  /// Creates a new streaming function call.
  StreamingFunctionCall({
    required this.itemId,
    required this.callId,
    required this.name,
    required this.outputIndex,
  });

  /// Item ID from the API.
  final String itemId;

  /// Call ID for this function call.
  final String callId;

  /// Name of the function being called.
  final String name;

  /// Output index where this function call appears.
  final int outputIndex;

  /// Accumulated arguments string.
  String arguments = '';

  /// Appends an arguments delta to the accumulated arguments.
  void appendArguments(String delta) {
    arguments += delta;
  }

  /// Whether the function call has complete arguments.
  bool get isComplete => arguments.isNotEmpty;
}
