import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

import '../chat_models/openai_responses/openai_responses_chat_model.dart';
import '../chat_models/openai_responses/openai_responses_chat_options.dart';
import '../media_models/openai_responses/openai_responses_media_model.dart';
import '../media_models/openai_responses/openai_responses_media_model_options.dart';
import '../platform/platform.dart';
import 'openai_provider_base.dart';

/// Provider for the OpenAI Responses API.
class OpenAIResponsesProvider
    extends
        OpenAIProviderBase<
          OpenAIResponsesChatModelOptions,
          OpenAIResponsesMediaModelOptions
        > {
  /// Creates a new OpenAI Responses provider instance.
  OpenAIResponsesProvider({String? apiKey, super.baseUrl, super.aliases})
    : super(
        name: providerName,
        displayName: providerDisplayName,
        defaultModelNames: const {
          ModelKind.chat: defaultChatModel,
          ModelKind.embeddings: defaultEmbeddingsModel,
          ModelKind.media: defaultMediaModel,
        },
        caps: const {
          ProviderCaps.chat,
          ProviderCaps.embeddings,
          ProviderCaps.multiToolCalls,
          ProviderCaps.typedOutput,
          ProviderCaps.typedOutputWithTools,
          ProviderCaps.thinking,
          ProviderCaps.chatVision,
          ProviderCaps.mediaGeneration,
        },
        apiKey: apiKey ?? tryGetEnv(defaultApiKeyName),
        apiKeyName: defaultApiKeyName,
      );

  static final Logger _logger = Logger(
    'dartantic.chat.providers.openai_responses',
  );

  @override
  Logger get logger => _logger;

  /// Canonical provider name.
  static const providerName = 'openai-responses';

  /// Human-friendly provider name.
  static const providerDisplayName = 'OpenAI Responses';

  /// Default chat model identifier.
  static const defaultChatModel = 'gpt-4o';

  /// Default embeddings model identifier.
  static const defaultEmbeddingsModel = 'text-embedding-3-small';

  /// Default media generation model identifier.
  static const defaultMediaModel = defaultChatModel;

  /// Environment variable used to read the API key.
  static const defaultApiKeyName = 'OPENAI_API_KEY';

  /// Default base URL for the OpenAI Responses API.
  /// Note: Points to the Responses API endpoint to work around a bug
  /// in openai_core v0.4.0 where it incorrectly constructs the URL path.
  static final defaultResponsesBaseUrl = Uri.parse(
    'https://api.openai.com/v1/responses',
  );

  /// Backwards-compatible alias for the default Responses endpoint.
  static final defaultBaseUrl = defaultResponsesBaseUrl;
  static final Uri _defaultApiBaseUrl = Uri.parse('https://api.openai.com/v1');

  @override
  ChatModel<OpenAIResponsesChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    OpenAIResponsesChatModelOptions? options,
  }) {
    validateApiKeyPresence();
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    _logger.info(
      'Creating OpenAI Responses chat model: $modelName '
      'with ${(tools ?? const []).length} tools, temp: $temperature, '
      'thinking: $enableThinking',
    );

    return OpenAIResponsesChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      apiKey: apiKey,
      baseUrl: baseUrl ?? defaultResponsesBaseUrl,
      defaultOptions: _mergeOptions(temperature, enableThinking, options),
    );
  }

  /// Merges temperature and options into a single options object.
  OpenAIResponsesChatModelOptions _mergeOptions(
    double? temperature,
    bool enableThinking,
    OpenAIResponsesChatModelOptions? options,
  ) {
    // If thinking is enabled and no explicit reasoningSummary, use detailed
    final reasoningSummary = enableThinking && options?.reasoningSummary == null
        ? OpenAIReasoningSummary.detailed
        : options?.reasoningSummary;

    return OpenAIResponsesChatModelOptions(
      temperature: temperature ?? options?.temperature,
      topP: options?.topP,
      maxOutputTokens: options?.maxOutputTokens,
      store: options?.store ?? true,
      metadata: options?.metadata,
      include: options?.include,
      parallelToolCalls: options?.parallelToolCalls,
      reasoning: options?.reasoning,
      reasoningEffort: options?.reasoningEffort,
      reasoningSummary: reasoningSummary,
      responseFormat: options?.responseFormat,
      truncationStrategy: options?.truncationStrategy,
      user: options?.user,
      imageDetail: options?.imageDetail,
      serverSideTools: options?.serverSideTools,
      fileSearchConfig: options?.fileSearchConfig,
      webSearchConfig: options?.webSearchConfig,
      codeInterpreterConfig: options?.codeInterpreterConfig,
    );
  }

  @override
  Uri get embeddingsApiBaseUrl => _defaultApiBaseUrl;

  @override
  Uri get modelsApiBaseUrl => _defaultApiBaseUrl;

  @override
  MediaGenerationModel<OpenAIResponsesMediaModelOptions> createMediaModel({
    String? name,
    List<Tool>? tools,
    OpenAIResponsesMediaModelOptions? options,
  }) {
    validateApiKeyPresence();
    final modelName = name ?? defaultModelNames[ModelKind.media]!;
    final defaultOptions = options ?? const OpenAIResponsesMediaModelOptions();

    _logger.info(
      'Creating OpenAI Responses media model: $modelName with '
      '${(tools ?? const []).length} tools',
    );

    final chatDefaultOptions = OpenAIResponsesMediaModel.buildChatOptions(
      defaultOptions,
    );

    final chatModel = OpenAIResponsesChatModel(
      name: modelName,
      tools: tools,
      apiKey: apiKey,
      baseUrl: baseUrl ?? defaultResponsesBaseUrl,
      defaultOptions: chatDefaultOptions,
    );

    return OpenAIResponsesMediaModel(
      name: modelName,
      tools: tools,
      defaultOptions: defaultOptions,
      chatModel: chatModel,
    );
  }
}
