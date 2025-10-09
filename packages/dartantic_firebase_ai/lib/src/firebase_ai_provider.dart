import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

import 'firebase_ai_chat_model.dart';
import 'firebase_ai_chat_options.dart';

/// Provider for Firebase AI (Gemini via Firebase).
///
/// Firebase AI provides access to Google's Gemini models through Firebase,
/// with additional features like App Check security and Firebase Auth integration.
class FirebaseAIProvider
    extends Provider<FirebaseAIChatModelOptions, EmbeddingsModelOptions> {
  /// Creates a new Firebase AI provider instance.
  ///
  /// Note: Firebase AI doesn't use traditional API keys. Authentication is
  /// handled through Firebase configuration and App Check.
  FirebaseAIProvider()
    : super(
        apiKey: null,
        apiKeyName: null,
        name: 'firebase_ai',
        displayName: 'Firebase AI',
        defaultModelNames: const {ModelKind.chat: 'gemini-2.0-flash'},
        caps: const {
          ProviderCaps.chat,
          ProviderCaps.multiToolCalls,
          ProviderCaps.typedOutput,
          ProviderCaps.chatVision,
          ProviderCaps.thinking,
        },
        aliases: const ['firebase'],
        baseUrl: null,
      );

  static final Logger _logger = Logger('dartantic.chat.providers.firebase_ai');

  /// Validates Firebase AI model name format.
  bool _isValidModelName(String modelName) {
    // Firebase AI uses Gemini models with format: gemini-<version>-<variant>
    return RegExp(r'^gemini-\d+(\.\d+)?(-\w+)?$').hasMatch(modelName);
  }

  @override
  ChatModel<FirebaseAIChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    FirebaseAIChatModelOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    // Validate temperature range
    if (temperature != null && (temperature < 0.0 || temperature > 2.0)) {
      throw ArgumentError(
        'Temperature must be between 0.0 and 2.0, got: $temperature',
      );
    }

    // Validate model name format
    if (!_isValidModelName(modelName)) {
      throw ArgumentError(
        'Invalid Firebase AI model name: $modelName. '
        'Expected format: gemini-<version>-<variant> (e.g., gemini-2.0-flash)',
      );
    }

    _logger.info(
      'Creating Firebase AI model: $modelName with '
      '${tools?.length ?? 0} tools, '
      'temp: $temperature',
    );

    return FirebaseAIChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      defaultOptions: FirebaseAIChatModelOptions(
        topP: options?.topP,
        topK: options?.topK,
        candidateCount: options?.candidateCount,
        maxOutputTokens: options?.maxOutputTokens,
        temperature: temperature ?? options?.temperature,
        stopSequences: options?.stopSequences,
        responseMimeType: options?.responseMimeType,
        responseSchema: options?.responseSchema,
        safetySettings: options?.safetySettings,
        enableCodeExecution: options?.enableCodeExecution,
      ),
    );
  }

  @override
  EmbeddingsModel<EmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    EmbeddingsModelOptions? options,
  }) {
    throw UnimplementedError(
      'Firebase AI does not currently support embeddings models',
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    // Firebase AI uses the same models as Google Gemini
    // We can yield the commonly available models
    yield ModelInfo(
      name: 'gemini-2.0-flash',
      providerName: name,
      kinds: {ModelKind.chat},
      displayName: 'Gemini 2.0 Flash',
      description:
          'Fast and versatile performance across a diverse variety of tasks',
    );
    yield ModelInfo(
      name: 'gemini-1.5-flash',
      providerName: name,
      kinds: {ModelKind.chat},
      displayName: 'Gemini 1.5 Flash',
      description:
          'Fast and versatile multimodal model for scaling across diverse tasks',
    );
    yield ModelInfo(
      name: 'gemini-1.5-pro',
      providerName: name,
      kinds: {ModelKind.chat},
      displayName: 'Gemini 1.5 Pro',
      description: 'Complex reasoning tasks requiring more intelligence',
    );
  }
}
