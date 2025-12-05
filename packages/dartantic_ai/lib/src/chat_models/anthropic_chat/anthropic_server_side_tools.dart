import 'anthropic_chat_options.dart';

/// Enumerates Anthropic server-side tools with convenience helpers.
enum AnthropicServerSideTool {
  /// Anthropic code execution sandbox.
  codeInterpreter,

  /// Anthropic web search tool.
  webSearch,

  /// Anthropic web fetch tool.
  webFetch,
}

/// Convenience extensions for [AnthropicServerSideTool].
extension AnthropicServerSideToolX on AnthropicServerSideTool {
  /// API tool type identifier.
  String get type => switch (this) {
    AnthropicServerSideTool.codeInterpreter => 'code_execution_20250825',
    AnthropicServerSideTool.webSearch => 'web_search_20250305',
    AnthropicServerSideTool.webFetch => 'web_fetch_20250910',
  };

  /// API tool name.
  String get apiName => switch (this) {
    AnthropicServerSideTool.codeInterpreter => 'code_execution',
    AnthropicServerSideTool.webSearch => 'web_search',
    AnthropicServerSideTool.webFetch => 'web_fetch',
  };

  /// Beta headers required to use this tool.
  List<String> get betaFeatures => switch (this) {
    AnthropicServerSideTool.codeInterpreter => const [
      'code-execution-2025-05-22',
      'code-execution-2025-08-25',
      'files-api-2025-04-14',
    ],
    AnthropicServerSideTool.webSearch => const ['web-search-2025-03-05'],
    AnthropicServerSideTool.webFetch => const ['web-fetch-2025-09-10'],
  };

  /// Whether Anthropic requires an explicit tool choice for this tool.
  bool get requiresExplicitChoice =>
      this == AnthropicServerSideTool.codeInterpreter;

  /// Builds the tool configuration payload for this tool.
  AnthropicServerToolConfig toConfig() =>
      AnthropicServerToolConfig(type: type, name: apiName);
}

/// Merges explicit tool configs and shorthand server-side tools.
List<AnthropicServerToolConfig> mergeAnthropicServerToolConfigs({
  List<AnthropicServerToolConfig>? manualConfigs,
  Set<AnthropicServerSideTool>? serverSideTools,
}) {
  final map = <String, AnthropicServerToolConfig>{};
  void addConfig(AnthropicServerToolConfig config) {
    map['${config.type}:${config.name}'] = config;
  }

  manualConfigs?.forEach(addConfig);
  serverSideTools?.forEach((tool) => addConfig(tool.toConfig()));

  return map.values.toList(growable: false);
}

/// Computes required beta headers for a set of tools.
List<String> betaFeaturesForAnthropicTools({
  List<AnthropicServerToolConfig>? manualConfigs,
  Set<AnthropicServerSideTool>? serverSideTools,
}) {
  final features = <String>{};

  manualConfigs?.forEach((config) {
    features.addAll(_betaFeaturesForConfig(config));
  });
  serverSideTools?.forEach((tool) {
    features.addAll(tool.betaFeatures);
  });

  return features.toList(growable: false);
}

List<String> _betaFeaturesForConfig(AnthropicServerToolConfig config) {
  switch (config.type) {
    case 'code_execution_20250825':
    case 'code_execution_20250522':
      return const [
        'code-execution-2025-05-22',
        'code-execution-2025-08-25',
        'files-api-2025-04-14',
      ];
    case 'web_search_20250305':
      return const ['web-search-2025-03-05'];
    case 'web_fetch_20250910':
      return const ['web-fetch-2025-09-10'];
    default:
      return const [];
  }
}
