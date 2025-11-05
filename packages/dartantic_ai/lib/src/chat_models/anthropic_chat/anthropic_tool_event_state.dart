import 'anthropic_server_side_tool_types.dart';

/// Mutable state for tracking Anthropic server-side tool events.
class AnthropicEventMappingState {
  /// Creates a new event mapping state.
  AnthropicEventMappingState();

  /// Aggregated tool events keyed by tool identifier.
  final Map<String, List<Map<String, Object?>>> toolEventLog = {
    AnthropicServerToolTypes.codeExecution: <Map<String, Object?>>[],
    AnthropicServerToolTypes.textEditorCodeExecution: <Map<String, Object?>>[],
    AnthropicServerToolTypes.bashCodeExecution: <Map<String, Object?>>[],
    AnthropicServerToolTypes.webSearch: <Map<String, Object?>>[],
    AnthropicServerToolTypes.webFetch: <Map<String, Object?>>[],
  };

  /// Records a tool event into the aggregated log.
  void recordToolEvent(String toolType, Map<String, Object?> event) {
    final bucket = toolEventLog.putIfAbsent(toolType, _createEventList);
    bucket.add(Map<String, Object?>.from(event));
  }

  /// Whether any tool events were recorded.
  bool get hasToolEvents =>
      toolEventLog.values.any((events) => events.isNotEmpty);

  /// Produces a deep copy of the aggregated tool events.
  Map<String, List<Map<String, Object?>>> toMetadata() => {
    for (final entry in toolEventLog.entries)
      if (entry.value.isNotEmpty) entry.key: _copyEventList(entry.value),
  };

  /// Clears any accumulated tool state after a message completes.
  void reset() {
    for (final events in toolEventLog.values) {
      events.clear();
    }
  }

  List<Map<String, Object?>> _copyEventList(
    List<Map<String, Object?>> source,
  ) => source.map(Map<String, Object?>.from).toList();

  static List<Map<String, Object?>> _createEventList() =>
      <Map<String, Object?>>[];
}
