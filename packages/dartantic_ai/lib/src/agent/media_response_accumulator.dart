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

  /// Adds a media generation chunk to the accumulator.
  void add(MediaGenerationResult chunk) {
    _assets.addAll(chunk.assets);
    _links.addAll(chunk.links);
    _messages.addAll(chunk.messages);

    for (final entry in chunk.metadata.entries) {
      _metadata[entry.key] = entry.value;
    }

    if (chunk.usage != null) {
      _usage = chunk.usage;
    }

    _finishReason = chunk.finishReason;
    _id = chunk.id;
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
  );
}
