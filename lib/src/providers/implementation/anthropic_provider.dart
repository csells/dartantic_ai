import '../../models/implementations/anthropic_model.dart';
import '../../models/interface/model.dart';
import '../../models/interface/model_settings.dart';
import '../../platform/platform.dart' as platform;
import '../interface/provider.dart';
import '../interface/provider_caps.dart';

/// Provider for Anthropic Claude models.
///
/// This provider creates instances of [AnthropicModel] using the specified
/// model name and API key.
class AnthropicProvider extends Provider {
  /// Creates a new [AnthropicProvider] with the given parameters.
  ///
  /// The [modelName] is the name of the Anthropic model to use.
  /// If not provided, [defaultModelName] is used.
  /// The [apiKey] is the API key to use for authentication.
  /// If not provided, it's retrieved from the environment.
  /// The [baseUrl] is the base URL for the Anthropic API.
  /// The [headers] are additional headers to include in requests.
  /// The [temperature] is the temperature to use for generation.
  /// The [maxTokens] is the maximum number of tokens to generate.
  AnthropicProvider({
    this.name = 'anthropic',
    this.modelName,
    String? apiKey,
    this.baseUrl = 'https://api.anthropic.com/v1',
    this.headers = const {},
    this.temperature,
    this.maxTokens = 64000,
    this.caps = const {
      ProviderCaps.textGeneration,
      ProviderCaps.chat,
      ProviderCaps.fileUploads,
      ProviderCaps.tools,
    },
  }) : apiKey = apiKey ?? platform.getEnv(apiKeyName);

  /// The name of the environment variable that contains the API key.
  static const apiKeyName = 'ANTHROPIC_API_KEY';

  /// The default model name to use if none is provided.
  static const defaultModelName = 'claude-sonnet-4-20250514';

  @override
  final String name;

  /// The name of the Anthropic model to use.
  final String? modelName;

  /// The API key to use for authentication with the Anthropic API.
  final String apiKey;

  /// The base URL for the Anthropic API.
  final String baseUrl;

  /// Additional headers to include in requests.
  final Map<String, String> headers;

  /// The temperature to use for generation.
  final double? temperature;

  /// The maximum number of tokens to generate.
  final int maxTokens;

  /// Creates a [Model] instance using this provider's configuration.
  ///
  /// The [settings] parameter contains additional configuration options
  /// for the model, such as the system prompt and output type.
  @override
  Model createModel(ModelSettings settings) => AnthropicModel(
    apiKey: apiKey,
    modelName: modelName ?? defaultModelName,
    systemPrompt: settings.systemPrompt,
    baseUrl: baseUrl,
    headers: headers,
    temperature: settings.temperature ?? temperature,
    maxTokens: maxTokens,
    tools: settings.tools,
    caps: caps,
  );

  @override
  final Set<ProviderCaps> caps;

  /// Anthropic doesn't provide a models endpoint
  @override
  Future<Iterable<ModelInfo>> listModels() async => [
    ModelInfo(
      name: 'claude-opus-4-20250514',
      providerName: name,
      kinds: {ModelKind.chat},
      stable: true,
    ),
    ModelInfo(
      name: 'claude-sonnet-4-20250514',
      providerName: name,
      kinds: {ModelKind.chat},
      stable: true,
    ),
    ModelInfo(
      name: 'claude-3-haiku-20240307',
      providerName: name,
      kinds: {ModelKind.chat},
      stable: true,
    ),
    ModelInfo(
      name: 'claude-3-sonnet-20240229',
      providerName: name,
      kinds: {ModelKind.chat},
      stable: true,
    ),
    ModelInfo(
      name: 'claude-3-opus-20240229',
      providerName: name,
      kinds: {ModelKind.chat},
      stable: true,
    ),
    ModelInfo(
      name: 'claude-3-5-sonnet-20240620',
      providerName: name,
      kinds: {ModelKind.chat},
      stable: true,
    ),
    ModelInfo(
      name: 'claude-3-5-sonnet-20241022',
      providerName: name,
      kinds: {ModelKind.chat},
      stable: true,
    ),
    ModelInfo(
      name: 'claude-3-5-haiku-20241022',
      providerName: name,
      kinds: {ModelKind.chat},
      stable: true,
    ),
    ModelInfo(
      name: 'claude-3-5-sonnet-latest',
      providerName: name,
      kinds: {ModelKind.chat},
      stable: false,
    ),
    ModelInfo(
      name: 'claude-3-5-haiku-latest',
      providerName: name,
      kinds: {ModelKind.chat},
      stable: false,
    ),
  ];
}
