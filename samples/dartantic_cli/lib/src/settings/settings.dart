/// Settings data model for CLI configuration
class Settings {
  Settings({
    this.defaultAgent,
    this.thinking,
    this.serverTools = true,
    this.chunkSize = 512,
    this.chunkOverlap = 100,
    this.agents = const {},
  });

  factory Settings.empty() => Settings();

  final String? defaultAgent;
  /// Global thinking setting. Null means use provider defaults.
  final bool? thinking;
  final bool serverTools;
  final int chunkSize;
  final int chunkOverlap;
  final Map<String, AgentSettings> agents;
}

/// Agent-specific settings
class AgentSettings {
  AgentSettings({
    required this.model,
    this.system,
    this.thinking,
    this.serverTools,
    this.outputSchema,
    this.apiKeyName,
    this.baseUrl,
    this.headers = const {},
    this.mcpServers = const [],
  });

  final String model;
  final String? system;
  final bool? thinking;
  final bool? serverTools;
  final Map<String, Object?>? outputSchema;
  final String? apiKeyName;
  final String? baseUrl;
  final Map<String, String> headers;
  final List<McpServerSettings> mcpServers;
}

/// MCP server configuration
class McpServerSettings {
  McpServerSettings({
    required this.name,
    this.url,
    this.headers = const {},
    this.command,
    this.args = const [],
    this.environment = const {},
    this.workingDirectory,
  });

  final String name;
  final String? url;
  final Map<String, String> headers;
  final String? command;
  final List<String> args;
  final Map<String, String> environment;
  final String? workingDirectory;
}
