import 'package:dartantic_interface/dartantic_interface.dart';

/// Accumulates streaming media generation chunks into a final result.
class MediaResponseAccumulator {
  /// Creates a new accumulator.
  MediaResponseAccumulator();

  final List<Part> _assets = <Part>[];
  final List<LinkPart> _links = <LinkPart>[];
  final List<ChatMessage> _messages = <ChatMessage>[];
  final Map<String, dynamic> _metadata = <String, dynamic>{};

  LanguageModelUsage? _usage;
  FinishReason _finishReason = FinishReason.unspecified;
  String? _id;
  bool _isComplete = false;

  /// Adds a media generation chunk to the accumulator.
  void add(MediaGenerationResult chunk) {
    _assets.addAll(chunk.assets);
    _links.addAll(chunk.links);
    _messages.addAll(chunk.messages);

    for (final entry in chunk.metadata.entries) {
      _mergeMetadata(entry.key, entry.value);
    }

    if (chunk.usage != null) {
      _usage = chunk.usage;
    }

    if (chunk.finishReason != FinishReason.unspecified) {
      _finishReason = chunk.finishReason;
    }
    if (chunk.id.isNotEmpty) {
      _id = chunk.id;
    }
    _isComplete =
        _isComplete ||
        chunk.isComplete ||
        chunk.finishReason != FinishReason.unspecified;
  }

  /// Builds the final aggregated media result.
  MediaGenerationResult buildFinal() => MediaGenerationResult(
    id: _id,
    assets: List<Part>.unmodifiable(_assets),
    links: List<LinkPart>.unmodifiable(_links),
    messages: List<ChatMessage>.unmodifiable(_messages),
    metadata: Map<String, dynamic>.unmodifiable(_metadata),
    usage: _usage,
    finishReason: _finishReason,
    isComplete: _isComplete || _finishReason != FinishReason.unspecified,
  );

  void _mergeMetadata(String key, dynamic value) {
    final current = _metadata[key];

    if (value is List) {
      final existing = current is List ? current : const [];
      _metadata[key] = <dynamic>[...existing, ...value];
      return;
    }

    if (value is Map) {
      final merged = <String, dynamic>{};
      if (current is Map) {
        for (final entry in current.entries) {
          merged[entry.key.toString()] = entry.value;
        }
      }
      for (final entry in value.entries) {
        merged[entry.key.toString()] = entry.value;
      }
      _metadata[key] = merged;
      return;
    }

    _metadata[key] = value;
  }
}
