import '../../models/implementations/gemini_model.dart';
import '../../platform/platform.dart' as platform;
import '../providers.dart';

/// Manages the mapping between provider family names and provider factories.
///
/// Provides a registry of available AI model providers and methods to create
/// provider instances based on settings.
class ProviderTable {
  /// Map of provider family names to provider factory functions.
  ///
  /// Used to look up the appropriate provider factory when creating providers.
  static final providers = <String, ProviderFactory>{
    'anthropic':
        (settings) => AnthropicProvider(
          modelName: settings.modelName,
          apiKey: settings.apiKey,
          caps: ProviderCaps.allExcept({
            ProviderCaps.embeddings,
            ProviderCaps.structuredOutput,
          }),
        ),
    'openai':
        (settings) => OpenAiProvider(
          modelName: settings.modelName,
          embeddingModelName: settings.embeddingModelName,
          apiKey: settings.apiKey,
          baseUrl: settings.baseUrl,
          caps: ProviderCaps.all,
          parallelToolCalls: true,
        ),
    'openrouter':
        (settings) => OpenAiProvider(
          name: 'openrouter',
          modelName: settings.modelName,
          embeddingModelName: settings.embeddingModelName,
          apiKey: settings.apiKey ?? platform.getEnv('OPENROUTER_API_KEY'),
          baseUrl:
              settings.baseUrl ?? Uri.parse('https://openrouter.ai/api/v1'),
          caps: ProviderCaps.allExcept({ProviderCaps.embeddings}),
          parallelToolCalls: true,
        ),
    'gemini-compat':
        // we're using the OpenAI-compatible Gemini API, but we still have to
        // use Google model names and API keys
        (settings) => OpenAiProvider(
          name: 'gemini-compat',
          modelName: settings.modelName ?? GeminiModel.defaultModelName,
          embeddingModelName:
              settings.embeddingModelName ??
              GeminiModel.defaultEmbeddingModelName,
          apiKey: settings.apiKey ?? platform.getEnv(GeminiProvider.apiKeyName),
          baseUrl:
              settings.baseUrl ??
              Uri.parse(
                'https://generativelanguage.googleapis.com/v1beta/openai',
              ),
          caps: ProviderCaps.all,
          parallelToolCalls: false,
        ),
    'google': (settings) {
      if (settings.baseUrl != null) {
        throw ArgumentError('Google provider does not support baseUrl');
      }

      return GeminiProvider(
        modelName: settings.modelName,
        embeddingModelName: settings.embeddingModelName,
        apiKey: settings.apiKey,
      );
    },
  };

  /// Aliases for provider names to support different naming conventions.
  static const providerAliases = {
    'claude': 'anthropic',
    'claude-ai': 'anthropic',
    'googleai': 'google',
    'google-gla': 'google',
    'gemini': 'google',
  };

  /// Creates a provider instance for the given settings.
  ///
  /// Uses the [settings providerName] to look up the appropriate provider
  /// factory in the [providers] map and creates a provider with the
  /// specified settings. Throws an [ArgumentError] if the provider family is
  /// not supported.
  static Provider providerFor(
    String name, {
    required ProviderSettings settings,
  }) {
    final providerName = providerAliases[name] ?? name;
    final providerFactory = providers[providerName];
    if (providerFactory != null) return providerFactory(settings);
    throw ArgumentError('Unsupported provider: $name');
  }
}
