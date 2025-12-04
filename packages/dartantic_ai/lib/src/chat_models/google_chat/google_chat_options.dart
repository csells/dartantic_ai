import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:meta/meta.dart';

import 'google_server_side_tools.dart' show GoogleServerSideTool;

/// Options to pass into the Google Generative AI Chat Model.
///
/// You can find a list of available models
/// [here](https://ai.google.dev/models).
@immutable
class GoogleChatModelOptions extends ChatModelOptions {
  /// Creates a new chat google generative ai options instance.
  const GoogleChatModelOptions({
    this.model,
    this.temperature,
    this.topP,
    this.topK,
    this.candidateCount,
    this.maxOutputTokens,
    this.stopSequences,
    this.responseMimeType,
    this.responseSchema,
    this.safetySettings,
    this.thinkingBudgetTokens,
    this.serverSideTools,
  });

  /// The model to use (e.g. 'gemini-1.5-pro').
  final String? model;

  /// The temperature to use.
  final double? temperature;

  /// The top P value to use.
  final double? topP;

  /// The top K value to use.
  final int? topK;

  /// Number of generated responses to return. This value must be between
  /// [1, 8], inclusive. If unset, this will default to 1.
  final int? candidateCount;

  /// The maximum number of tokens to include in a candidate. If unset,
  /// this will default to `output_token_limit` specified in the `Model`
  /// specification.
  final int? maxOutputTokens;

  /// The set of character sequences (up to 5) that will stop output generation.
  /// If specified, the API will stop at the first appearance of a stop
  /// sequence. The stop sequence will not be included as part of the response.
  final List<String>? stopSequences;

  /// Output response mimetype of the generated candidate text.
  ///
  /// Supported mimetype:
  /// - `text/plain`: (default) Text output.
  /// - `application/json`: JSON response in the candidates.
  final String? responseMimeType;

  /// Output response schema of the generated candidate text.
  /// Following the [JSON Schema specification](https://json-schema.org).
  ///
  /// - Note: This only applies when the specified ``responseMIMEType`` supports
  ///   a schema; currently this is limited to `application/json`.
  ///
  /// Example:
  /// ```json
  /// {
  ///   'type': 'object',
  ///   'properties': {
  ///     'answer': {
  ///       'type': 'string',
  ///       'description': 'The answer to the question being asked',
  ///     },
  ///     'sources': {
  ///       'type': 'array',
  ///       'items': {'type': 'string'},
  ///       'description': 'The sources used to answer the question',
  ///     },
  ///   },
  ///   'required': ['answer', 'sources'],
  /// },
  /// ```
  final Map<String, dynamic>? responseSchema;

  /// A list of unique [ChatGoogleGenerativeAISafetySetting] instances for
  /// blocking unsafe content.
  ///
  /// This will be enforced on the generated output. There should not be more
  /// than one setting for each type. The API will block any contents and
  /// responses that fail to meet the thresholds set by these settings.
  ///
  /// This list overrides the default settings for each category specified. If
  /// there is no safety setting for a given category provided in the list, the
  /// API will use the default safety setting for that category.
  final List<ChatGoogleGenerativeAISafetySetting>? safetySettings;

  /// Optional token budget for thinking.
  ///
  /// Only applies when thinking is enabled at the Agent level via
  /// `Agent(model, enableThinking: true)`.
  ///
  /// Controls how many tokens Gemini can use for its internal reasoning.
  /// The range varies by model:
  /// - Gemini 2.5 Pro: 128-32768 (default: dynamic)
  /// - Gemini 2.5 Flash: 0-24576 (default: dynamic)
  /// - Gemini 2.5 Flash-Lite: 512-24576 (no default)
  ///
  /// Set to -1 for dynamic thinking (model decides budget based on complexity).
  /// If not specified when thinking is enabled, uses dynamic thinking (-1).
  ///
  /// Example:
  /// ```dart
  /// Agent(
  ///   'google:gemini-2.5-flash',
  ///   enableThinking: true,
  ///   chatModelOptions: GoogleChatModelOptions(
  ///     thinkingBudgetTokens: 8192,  // Override default dynamic budget
  ///   ),
  /// )
  /// ```
  final int? thinkingBudgetTokens;

  /// The server-side tools to enable.
  final Set<GoogleServerSideTool>? serverSideTools;
}

/// {@template chat_google_generative_ai_safety_setting}
/// Safety setting, affecting the safety-blocking behavior.
/// Passing a safety setting for a category changes the allowed probability that
/// content is blocked.
/// {@endtemplate}
class ChatGoogleGenerativeAISafetySetting {
  /// {@macro chat_google_generative_ai_safety_setting}
  const ChatGoogleGenerativeAISafetySetting({
    required this.category,
    required this.threshold,
  });

  /// The category for this setting.
  final ChatGoogleGenerativeAISafetySettingCategory category;

  /// Controls the probability threshold at which harm is blocked.
  final ChatGoogleGenerativeAISafetySettingThreshold threshold;
}

/// Safety settings categorizes.
///
/// Docs: https://ai.google.dev/docs/safety_setting_gemini
enum ChatGoogleGenerativeAISafetySettingCategory {
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
///
/// Docs: https://ai.google.dev/docs/safety_setting_gemini
enum ChatGoogleGenerativeAISafetySettingThreshold {
  /// Threshold is unspecified, block using default threshold.
  unspecified,

  /// 	Block when low, medium or high probability of unsafe content.
  blockLowAndAbove,

  /// Block when medium or high probability of unsafe content.
  blockMediumAndAbove,

  /// Block when high probability of unsafe content.
  blockOnlyHigh,

  /// Always show regardless of probability of unsafe content.
  blockNone,
}
