/// Parses a model string into a provider name, chat model name, and embeddings
/// model name.
class ModelStringParser {
  /// Parses a model string into a provider name, chat model name, and
  /// embeddings model name.
  ModelStringParser(
    this.providerName, {
    this.chatModelName,
    this.embeddingsModelName,
    this.mediaModelName,
  });

  /// Parses a model string into provider, chat, and embeddings model names.
  ///
  /// Supports the following relative URI formats:
  /// - `providerName`
  /// - `providerName:chatModel`
  /// - `providerName/chatModel`
  /// - `providerName?chat=chatModel`
  /// - `providerName?embeddings=embeddingsModel`
  /// - `providerName?media=mediaModel`
  /// - `providerName?chat=...&embeddings=...&media=...`
  factory ModelStringParser.parse(String model) {
    Never doThrow(String model) =>
        throw Exception('Invalid model string format: "$model".');

    // Try parsing as a relative URI
    final uri = Uri.tryParse(model);
    if (uri != null) {
      late final String provider;
      late final String? chat;
      late final String? embed;
      late final String? media;

      if (uri.isAbsolute) {
        // e.g. anthropic:claude-3-5-sonnet or openrouter:google/gemini-2.0-flash
        provider = uri.scheme;
        // The path might contain slashes (e.g., google/gemini-2.0-flash)
        // Remove leading slash if present
        chat = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
        embed = null;
        media = null;
      } else if (uri.pathSegments.length == 1) {
        // e.g. anthropic?chat=claude-3-5-sonnet&...
        provider = uri.pathSegments.first;
        chat = uri.queryParameters['chat'];
        embed = uri.queryParameters['embeddings'];
        media = uri.queryParameters['media'] ?? uri.queryParameters['other'];
      } else if (uri.pathSegments.length == 2) {
        // e.g. anthropic/claude-3-5-sonnet
        provider = uri.pathSegments.first;
        chat = uri.pathSegments.last;
        embed = null;
        media = null;
      } else {
        doThrow(model);
      }

      return ModelStringParser(
        // Uri.scheme is always lowercase, so force lowercase for consistency
        provider.toLowerCase(),
        chatModelName: chat?.isNotEmpty ?? false ? chat : null,
        embeddingsModelName: embed?.isNotEmpty ?? false ? embed : null,
        mediaModelName: media?.isNotEmpty ?? false ? media : null,
      );
    }

    doThrow(model);
  }

  /// The provider name.
  final String providerName;

  /// The chat model name.
  final String? chatModelName;

  /// The embeddings model name.
  final String? embeddingsModelName;

  /// The media generation model name.
  final String? mediaModelName;

  @override
  String toString() {
    if (chatModelName == null &&
        embeddingsModelName == null &&
        mediaModelName == null) {
      return providerName;
    }

    if (chatModelName != null &&
        embeddingsModelName == null &&
        mediaModelName == null) {
      return '$providerName:$chatModelName';
    }

    return Uri(
      path: providerName,
      queryParameters: {
        if (chatModelName != null) 'chat': chatModelName,
        if (embeddingsModelName != null) 'embeddings': embeddingsModelName,
        if (mediaModelName != null) 'media': mediaModelName,
      },
    ).toString();
  }
}
