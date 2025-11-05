import 'package:dartantic_interface/dartantic_interface.dart';

import '../../chat_models/openai_responses/openai_responses_chat_options.dart';

/// Options for configuring OpenAI Responses media generation runs.
class OpenAIResponsesMediaGenerationModelOptions
    extends MediaGenerationModelOptions {
  /// Creates a new set of media generation options.
  const OpenAIResponsesMediaGenerationModelOptions({
    this.partialImages,
    this.quality,
    this.size,
    this.store,
    this.metadata,
    this.include,
    this.user,
  });

  /// Number of progressive preview images to stream (0-3).
  final int? partialImages;

  /// Target image quality.
  final ImageGenerationQuality? quality;

  /// Target output size.
  final ImageGenerationSize? size;

  /// Whether to persist the Responses session on the server.
  final bool? store;

  /// Additional metadata forwarded to the OpenAI Responses API.
  final Map<String, dynamic>? metadata;

  /// Specific response fields to include.
  final List<String>? include;

  /// End-user identifier for abuse monitoring.
  final String? user;
}
