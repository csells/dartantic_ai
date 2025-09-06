/// Model-specific behavior and capabilities for OpenAI Responses API.
class OpenAIResponsesModelConfig {
  /// The model configurations.
  static const Map<String, ModelConfig> modelConfigs = {
    'gpt-5': ModelConfig(supportsTemperature: false),
    'gpt-5-pro': ModelConfig(supportsTemperature: false),
    'gpt-4o': ModelConfig(supportsTemperature: true),
    'gpt-4o-mini': ModelConfig(supportsTemperature: true),
    // O-series reasoning models do not accept temperature in Responses API
    'o3-mini': ModelConfig(supportsTemperature: false),
    'o3': ModelConfig(supportsTemperature: false),
    'o4': ModelConfig(supportsTemperature: false),
  };

  /// Returns true if the given model supports the `temperature` parameter.
  static bool supportsTemperature(String model) {
    // Exact match first
    final exact = modelConfigs[model];
    if (exact != null) return exact.supportsTemperature;

    // Heuristic patterns
    final m = model.toLowerCase();
    if (m.startsWith('gpt-5')) return false;
    if (m.startsWith('o3') || m.startsWith('o4')) return false;
    if (m.startsWith('gpt-4o')) return true;

    // Default: allow temperature unless we know it causes errors
    return true;
  }
}

/// Model configuration.
class ModelConfig {
  /// Creates a new model configuration instance.
  const ModelConfig({required this.supportsTemperature});

  /// Whether the model supports the `temperature` parameter.
  final bool supportsTemperature;
}
