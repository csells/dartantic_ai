import '../chat/chat_message.dart';
import '../model/finish_reason.dart';
import '../model/language_model_result.dart';

/// Streaming chunk returned by a media generation model.
///
/// Each chunk represents the latest state of an in-flight media run. Providers
/// should incrementally emit new assets, links, metadata, and usage updates.
class MediaGenerationResult extends LanguageModelResult<List<Part>> {
  /// Creates a new media generation result chunk.
  MediaGenerationResult({
    List<Part> assets = const [],
    List<LinkPart> links = const [],
    List<ChatMessage> messages = const [],
    this.isComplete = false,
    super.finishReason = FinishReason.unspecified,
    Map<String, dynamic> metadata = const {},
    super.usage,
    super.id,
  }) : _links = List<LinkPart>.unmodifiable(links),
       _messages = List<ChatMessage>.unmodifiable(messages),
       super(
         output: List<Part>.unmodifiable(assets),
         metadata: Map<String, dynamic>.unmodifiable(metadata),
       );

  /// Convenience getter for access to the emitted assets.
  List<Part> get assets => output;

  final List<LinkPart> _links;

  /// Hosted links associated with this chunk.
  List<LinkPart> get links => _links;

  final List<ChatMessage> _messages;

  /// Messages generated during the media run.
  List<ChatMessage> get messages => _messages;

  /// Whether this chunk marks completion of the media generation request.
  final bool isComplete;
}
