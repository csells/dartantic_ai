import 'package:json_schema/json_schema.dart';

import '../chat/chat_message.dart';
import '../tool.dart';
import 'media_generation_model_options.dart';
import 'media_generation_result.dart';

/// Base class for media generation models.
abstract class MediaGenerationModel<
  TOptions extends MediaGenerationModelOptions
> {
  /// Creates a new media generation model instance.
  MediaGenerationModel({
    required this.name,
    required this.defaultOptions,
    this.tools,
  });

  /// The model name to use.
  final String name;

  /// The default options for the media generation model.
  final TOptions defaultOptions;

  /// Optional tools that should be available to the media model.
  final List<Tool>? tools;

  /// Generates media content as a stream of [MediaGenerationResult] chunks.
  ///
  /// Implementations must validate requested [mimeTypes] before invoking the
  /// upstream API and reject unsupported requests with descriptive errors.
  /// Returned streams should emit incremental chunks that track progress,
  /// accumulate metadata, and mark the terminal chunk with `isComplete = true`.
  Stream<MediaGenerationResult> generateMediaStream(
    String prompt, {
    required List<String> mimeTypes,
    List<ChatMessage> history = const [],
    List<Part> attachments = const [],
    TOptions? options,
    JsonSchema? outputSchema,
  });

  /// Disposes the media generation model.
  void dispose();
}
