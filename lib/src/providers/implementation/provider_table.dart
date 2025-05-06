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
    'openai':
        (settings) => OpenAiProvider(
          modelName: settings.modelName,
          apiKey: settings.apiKey,
        ),
    'gemini':
        (settings) => GeminiProvider(
          modelName: settings.modelName,
          apiKey: settings.apiKey,
        ),
    'google':
        (settings) => GeminiProvider(
          modelName: settings.modelName,
          apiKey: settings.apiKey,
        ),
    'google-gla':
        (settings) => GeminiProvider(
          modelName: settings.modelName,
          apiKey: settings.apiKey,
        ),
  };

  /// Creates a provider instance for the given settings.
  ///
  /// Uses the [settings familyName] to look up the appropriate provider factory
  /// in the [providers] map and creates a provider with the specified settings.
  /// Throws an [ArgumentError] if the provider family is not supported.
  static Provider providerFor(ProviderSettings settings) {
    final providerFactory = providers[settings.familyName];
    if (providerFactory != null) return providerFactory(settings);
    throw ArgumentError('Unsupported provider family: $settings.family');
  }
}
