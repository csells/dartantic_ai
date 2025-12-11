import 'package:dartantic_interface/dartantic_interface.dart';

import '../../chat_models/google_chat/google_chat_options.dart';

/// Options for configuring Google Gemini media generation.
class GoogleMediaGenerationModelOptions extends MediaGenerationModelOptions {
  /// Creates a new set of media options for Google Gemini.
  const GoogleMediaGenerationModelOptions({
    this.temperature,
    this.topP,
    this.topK,
    this.maxOutputTokens,
    this.safetySettings,
    this.responseMimeType,
    this.imageSampleCount,
    this.aspectRatio,
    this.responseModalities,
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

  /// The modalities to include in the response (e.g. `['TEXT', 'IMAGE']`).
  final List<String>? responseModalities;
}
