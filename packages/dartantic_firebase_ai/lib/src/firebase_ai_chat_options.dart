import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:meta/meta.dart';

/// Options to pass into the Firebase AI Chat Model.
///
/// Firebase AI uses Gemini models through Firebase.
@immutable
class FirebaseAIChatModelOptions extends ChatModelOptions {
  /// Creates a new Firebase AI chat options instance.
  const FirebaseAIChatModelOptions({
    this.topP,
    this.topK,
    this.candidateCount,
    this.maxOutputTokens,
    this.temperature,
    this.stopSequences,
    this.responseMimeType,
    this.responseSchema,
    this.safetySettings,
    this.enableCodeExecution,
  });

  /// The maximum cumulative probability of tokens to consider when sampling.
  final double? topP;

  /// The maximum number of tokens to consider when sampling.
  final int? topK;

  /// Number of generated responses to return.
  final int? candidateCount;

  /// The maximum number of tokens to include in a candidate.
  final int? maxOutputTokens;

  /// Controls the randomness of the output.
  final double? temperature;

  /// Character sequences that will stop output generation.
  final List<String>? stopSequences;

  /// Output response mimetype of the generated candidate text.
  final String? responseMimeType;

  /// Output response schema of the generated candidate text.
  final Map<String, dynamic>? responseSchema;

  /// Safety settings for blocking unsafe content.
  final List<FirebaseAISafetySetting>? safetySettings;

  /// Enable code execution in the model.
  final bool? enableCodeExecution;
}

/// Safety setting for Firebase AI.
class FirebaseAISafetySetting {
  /// Creates a safety setting.
  const FirebaseAISafetySetting({
    required this.category,
    required this.threshold,
  });

  /// The category for this setting.
  final FirebaseAISafetySettingCategory category;

  /// Controls the probability threshold at which harm is blocked.
  final FirebaseAISafetySettingThreshold threshold;
}

/// Safety settings categories.
enum FirebaseAISafetySettingCategory {
  /// The harm category is unspecified.
  unspecified,

  /// The harm category is harassment.
  harassment,

  /// The harm category is hate speech.
  hateSpeech,

  /// The harm category is sexually explicit content.
  sexuallyExplicit,

  /// The harm category is dangerous content.
  dangerousContent,
}

/// Controls the probability threshold at which harm is blocked.
enum FirebaseAISafetySettingThreshold {
  /// Threshold is unspecified, block using default threshold.
  unspecified,

  /// Block when low, medium or high probability of unsafe content.
  blockLowAndAbove,

  /// Block when medium or high probability of unsafe content.
  blockMediumAndAbove,

  /// Block when high probability of unsafe content.
  blockOnlyHigh,

  /// Always show regardless of probability of unsafe content.
  blockNone,
}
