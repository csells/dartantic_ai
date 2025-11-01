import 'package:dartantic_interface/dartantic_interface.dart';

import '../../chat_models/google_chat/google_chat_options.dart';

/// Options for configuring Google Gemini media generation.
class GoogleMediaModelOptions extends MediaGenerationModelOptions {
  /// Creates a new set of media options for Google Gemini.
  const GoogleMediaModelOptions({
    this.temperature,
    this.topP,
    this.topK,
    this.maxOutputTokens,
    this.safetySettings,
    this.responseMimeType,
    this.imageSampleCount,
    this.aspectRatio,
    this.negativePrompt,
    this.addWatermark,
    this.imagenModel,
  });

  /// Sampling temperature for generated content.
  final double? temperature;

  /// nucleus sampling parameter.
  final double? topP;

  /// top-k sampling parameter.
  final int? topK;

  /// Maximum number of output tokens.
  final int? maxOutputTokens;

  /// Safety settings applied to the request.
  final List<ChatGoogleGenerativeAISafetySetting>? safetySettings;

  /// Explicit MIME type to request from the API.
  ///
  /// When null, the first supported MIME type from the request is used.
  final String? responseMimeType;

  /// Number of images to generate when using Imagen.
  final int? imageSampleCount;

  /// Target aspect ratio for generated images (for example, `16:9`).
  final String? aspectRatio;

  /// Negative prompt used to discourage specific content.
  final String? negativePrompt;

  /// Whether to embed a Google watermark in generated images.
  final bool? addWatermark;

  /// Optional override for the Imagen model identifier.
  final String? imagenModel;
}
