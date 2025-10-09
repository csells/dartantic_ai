import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

import 'firebase_ai_chat_model.dart';
import 'firebase_ai_chat_options.dart';

/// Backend type for Firebase AI provider.
enum FirebaseAIBackend {
  /// Direct Google AI API - simpler setup, good for development/testing.
  googleAI,
  
  /// Vertex AI through Firebase - production-ready with Firebase features.
  vertexAI,
}

/// Provider for Firebase AI (Gemini via Firebase).
///
/// Firebase AI provides access to Google's Gemini models through Firebase,
/// supporting both GoogleAI (direct API) and VertexAI (through Firebase)
/// backends for flexible development and production deployment.
class FirebaseAIProvider
    extends Provider<FirebaseAIChatModelOptions, EmbeddingsModelOptions> {
  // IMPORTANT: Logger must be private (_logger not log) and static final
  static final Logger _logger = Logger('dartantic.chat.providers.firebase_ai');

  /// Default base URL for Firebase AI.
  /// Note: Firebase AI uses Firebase SDK, not direct REST API calls.
  static final defaultBaseUrl = Uri.parse('https://firebaseai.googleapis.com/v1');

  /// Creates a new Firebase AI provider instance.
  ///
  /// [backend] determines which Firebase AI backend to use:
  /// - [FirebaseAIBackend.googleAI]: Direct Google AI API (simpler setup)
  /// - [FirebaseAIBackend.vertexAI]: Vertex AI through Firebase (production)
  ///
  /// Note: Firebase AI doesn't use traditional API keys. Authentication is
  /// handled through Firebase configuration and App Check.
  FirebaseAIProvider({
    this.backend = FirebaseAIBackend.vertexAI,
    super.baseUrl,  // Use super.baseUrl, don't provide defaults here
  }) : super(
        apiKey: null,
        apiKeyName: null,
        name: 'firebase_ai',
        displayName: backend == FirebaseAIBackend.googleAI 
            ? 'Firebase AI (Google AI)' 
            : 'Firebase AI (Vertex AI)',
        defaultModelNames: const {ModelKind.chat: 'gemini-2.0-flash'},
        caps: const {
          ProviderCaps.chat,
          ProviderCaps.multiToolCalls,
          ProviderCaps.typedOutput,
          ProviderCaps.chatVision,
          ProviderCaps.thinking,
        },
        aliases: const ['firebase'],
      );

  /// The backend type this provider instance uses.
  final FirebaseAIBackend backend;

  /// Validates Firebase AI model name format.
  bool _isValidModelName(String modelName) =>
      // Firebase AI uses Gemini models with format: gemini-<version>-<variant>
      RegExp(r'^gemini-\d+(\.\d+)?(-\w+)?$').hasMatch(modelName);

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
      'Creating Firebase AI model: $modelName (${backend.name}) with '
      '${tools?.length ?? 0} tools, '
      'temp: $temperature',
    );

    return FirebaseAIChatModel(
      name: modelName,
      baseUrl: baseUrl ?? defaultBaseUrl,  // IMPORTANT: Pass baseUrl with fallback
      tools: tools,
      temperature: temperature,
      backend: backend,
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
      description: 'Fast and versatile multimodal model for scaling across '
          'diverse tasks',
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
