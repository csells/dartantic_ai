import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

import '../chat_models/openai_chat/openai_chat_model.dart';
import '../chat_models/openai_chat/openai_chat_options.dart';
import '../embeddings_models/openai_embeddings/openai_embeddings.dart';
import '../platform/platform.dart';
import '../shared/openai_utils.dart';

/// Provider for OpenAI-compatible APIs (OpenAI, Cohere, Together, etc.).
/// Handles API key, base URL, and model configuration.
class OpenAIProvider
    extends Provider<OpenAIChatOptions, OpenAIEmbeddingsModelOptions> {
  /// Creates a new OpenAI provider instance.
  ///
  /// - [name]: The canonical provider name (e.g., 'openai', 'cohere').
  /// - [displayName]: Human-readable name for display.
  /// - [defaultModelNames]: The default model for this provider.
  /// - [baseUrl]: The default API endpoint.
  /// - [apiKeyName]: The environment variable for the API key (if any).
  /// - [apiKey]: The API key for the OpenAI provider
  OpenAIProvider({
    String? apiKey,
    super.name = 'openai',
    super.displayName = 'OpenAI',
    super.defaultModelNames = const {
      ModelKind.chat: 'gpt-4o',
      ModelKind.embeddings: 'text-embedding-3-small',
    },
    super.caps = const {
      ProviderCaps.chat,
      ProviderCaps.embeddings,
      ProviderCaps.multiToolCalls,
      ProviderCaps.typedOutput,
      ProviderCaps.typedOutputWithTools,
      ProviderCaps.vision,
    },
    super.baseUrl,
    super.apiKeyName = 'OPENAI_API_KEY',
    super.aliases,
  }) : super(apiKey: apiKey ?? tryGetEnv(apiKeyName));

  static final Logger _logger = Logger('dartantic.chat.providers.openai');

  /// The environment variable for the API key
  static const defaultApiKeyName = 'OPENAI_API_KEY';

  /// The default base URL for the OpenAI API.
  static final defaultBaseUrl = Uri.parse('https://api.openai.com/v1');

  @override
  ChatModel<OpenAIChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    OpenAIChatOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    _logger.info(
      'Creating OpenAI model: $modelName with '
      '${tools?.length ?? 0} tools, '
      'temperature: $temperature',
    );

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    return OpenAIChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      apiKey: apiKey ?? tryGetEnv(apiKeyName),
      baseUrl: baseUrl,
      defaultOptions: OpenAIChatOptions(
        temperature: temperature ?? options?.temperature,
        topP: options?.topP,
        n: options?.n,
        maxTokens: options?.maxTokens,
        presencePenalty: options?.presencePenalty,
        frequencyPenalty: options?.frequencyPenalty,
        logitBias: options?.logitBias,
        stop: options?.stop,
        user: options?.user,
        responseFormat: options?.responseFormat,
        seed: options?.seed,
        parallelToolCalls: options?.parallelToolCalls,
        streamOptions: options?.streamOptions,
        serviceTier: options?.serviceTier,
      ),
    );
  }

  @override
  EmbeddingsModel<OpenAIEmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    OpenAIEmbeddingsModelOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.embeddings]!;

    _logger.info(
      'Creating OpenAI embeddings model: $modelName with '
      'options: $options',
    );

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    return OpenAIEmbeddingsModel(
      name: modelName,
      apiKey: apiKey ?? tryGetEnv(apiKeyName),
      baseUrl: baseUrl,
      dimensions: options?.dimensions,
      batchSize: options?.batchSize,
      user: options?.user,
      options: options,
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    final resolvedBaseUrl = baseUrl ?? defaultBaseUrl;
    yield* OpenAIUtils.listOpenAIModels(
      baseUrl: resolvedBaseUrl,
      providerName: name,
      logger: _logger,
      apiKey: apiKey,
    );
  }
}
