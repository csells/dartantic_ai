import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:openai_dart/openai_dart.dart';

import '../chat_models/openai_chat/openai_chat_model.dart';
import '../chat_models/openai_chat/openai_chat_options.dart';
import '../platform/platform.dart';
import 'openai_provider_base.dart';

/// Provider for OpenAI-compatible APIs (OpenAI, Cohere, Together, etc.).
/// Handles API key, base URL, and model configuration.
class OpenAIProvider
    extends OpenAIProviderBase<OpenAIChatOptions, MediaGenerationModelOptions> {
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
      ProviderCaps.chatVision,
    },
    super.baseUrl,
    super.apiKeyName = 'OPENAI_API_KEY',
    super.aliases,
    super.headers,
  }) : super(apiKey: apiKey ?? tryGetEnv(apiKeyName));

  static final Logger _logger = Logger('dartantic.chat.providers.openai');

  @override
  Logger get logger => _logger;

  /// The environment variable for the API key
  static const defaultApiKeyName = 'OPENAI_API_KEY';

  /// The default base URL for the OpenAI API.
  static final defaultBaseUrl = Uri.parse('https://api.openai.com/v1');

  @override
  ChatModel<OpenAIChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    OpenAIChatOptions? options,
  }) {
    if (enableThinking) {
      throw UnsupportedError(
        'Extended thinking is not supported by the $displayName provider. '
        'Only OpenAI Responses, Anthropic, and Google providers support '
        'thinking. Set enableThinking=false or use a provider that supports '
        'this feature.',
      );
    }

    validateApiKeyPresence();
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    _logger.info(
      'Creating OpenAI model: $modelName with '
      '${tools?.length ?? 0} tools, '
      'temperature: $temperature',
    );

    return OpenAIChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      apiKey: apiKey ?? tryGetEnv(apiKeyName),
      baseUrl: baseUrl,
      headers: headers,
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
        streamOptions:
            options?.streamOptions ??
            const ChatCompletionStreamOptions(includeUsage: true),
        serviceTier: options?.serviceTier,
      ),
    );
  }
}
