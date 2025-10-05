import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

import '../chat_models/openai_responses/openai_responses_chat_model.dart';
import '../chat_models/openai_responses/openai_responses_chat_options.dart';
import '../embeddings_models/openai_embeddings/openai_embeddings_model.dart';
import '../embeddings_models/openai_embeddings/openai_embeddings_model_options.dart';
import '../platform/platform.dart';
import '../shared/openai_utils.dart';

/// Provider for the OpenAI Responses API.
class OpenAIResponsesProvider
    extends
        Provider<
          OpenAIResponsesChatModelOptions,
          OpenAIEmbeddingsModelOptions
        > {
  /// Creates a new OpenAI Responses provider instance.
  OpenAIResponsesProvider({String? apiKey, super.baseUrl, super.aliases})
    : super(
        name: providerName,
        displayName: providerDisplayName,
        defaultModelNames: const {
          ModelKind.chat: defaultChatModel,
          ModelKind.embeddings: defaultEmbeddingsModel,
        },
        caps: const {
          ProviderCaps.chat,
          ProviderCaps.embeddings,
          ProviderCaps.multiToolCalls,
          ProviderCaps.typedOutput,
          ProviderCaps.typedOutputWithTools,
          ProviderCaps.thinking,
          ProviderCaps.vision,
        },
        apiKey: apiKey ?? tryGetEnv(defaultApiKeyName),
        apiKeyName: defaultApiKeyName,
      );

  static final Logger _logger = Logger(
    'dartantic.chat.providers.openai_responses',
  );

  /// Canonical provider name.
  static const providerName = 'openai-responses';

  /// Human-friendly provider name.
  static const providerDisplayName = 'OpenAI Responses';

  /// Default chat model identifier.
  static const defaultChatModel = 'gpt-4o';

  /// Default embeddings model identifier.
  static const defaultEmbeddingsModel = 'text-embedding-3-small';

  /// Environment variable used to read the API key.
  static const defaultApiKeyName = 'OPENAI_API_KEY';

  /// Default base URL for the OpenAI Responses API.
  /// Note: Points to the Responses API endpoint to work around a bug
  /// in openai_core v0.4.0 where it incorrectly constructs the URL path.
  static final defaultBaseUrl = Uri.parse(
    'https://api.openai.com/v1/responses',
  );

  @override
  ChatModel<OpenAIResponsesChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    OpenAIResponsesChatModelOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    _logger.info(
      'Creating OpenAI Responses chat model: $modelName '
      'with ${(tools ?? const []).length} tools, temp: $temperature',
    );

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    return OpenAIResponsesChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      apiKey: apiKey,
      baseUrl: baseUrl ?? defaultBaseUrl,
      defaultOptions: _mergeOptions(temperature, options),
    );
  }

  /// Merges temperature and options into a single options object.
  OpenAIResponsesChatModelOptions _mergeOptions(
    double? temperature,
    OpenAIResponsesChatModelOptions? options,
  ) => OpenAIResponsesChatModelOptions(
    temperature: temperature ?? options?.temperature,
    topP: options?.topP,
    maxOutputTokens: options?.maxOutputTokens,
    store: options?.store ?? true,
    metadata: options?.metadata,
    include: options?.include,
    parallelToolCalls: options?.parallelToolCalls,
    toolChoice: options?.toolChoice,
    reasoning: options?.reasoning,
    reasoningEffort: options?.reasoningEffort,
    reasoningSummary: options?.reasoningSummary,
    responseFormat: options?.responseFormat,
    truncationStrategy: options?.truncationStrategy,
    user: options?.user,
    imageDetail: options?.imageDetail,
    serverSideTools: options?.serverSideTools,
    fileSearchConfig: options?.fileSearchConfig,
    webSearchConfig: options?.webSearchConfig,
    codeInterpreterConfig: options?.codeInterpreterConfig,
  );

  @override
  EmbeddingsModel<OpenAIEmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    OpenAIEmbeddingsModelOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.embeddings]!;

    _logger.info('Creating OpenAI Responses embeddings model: $modelName');

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    // Embeddings use the standard API endpoint, not Responses
    final embeddingsBaseUrl = baseUrl ?? Uri.parse('https://api.openai.com/v1');

    return OpenAIEmbeddingsModel(
      name: modelName,
      apiKey: apiKey,
      baseUrl: embeddingsBaseUrl,
      dimensions: options?.dimensions,
      batchSize: options?.batchSize,
      options: OpenAIEmbeddingsModelOptions(
        dimensions: options?.dimensions,
        batchSize: options?.batchSize,
        user: options?.user,
      ),
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    // Use standard API endpoint for listing models, not the Responses endpoint
    final resolvedBaseUrl = baseUrl ?? Uri.parse('https://api.openai.com/v1');
    yield* OpenAIUtils.listOpenAIModels(
      baseUrl: resolvedBaseUrl,
      providerName: name,
      logger: _logger,
      apiKey: apiKey,
    );
  }
}
