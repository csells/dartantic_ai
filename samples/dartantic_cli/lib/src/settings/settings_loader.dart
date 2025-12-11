import 'dart:io';

import 'package:yaml/yaml.dart';

import 'settings.dart';

/// Loads and parses settings from YAML file
class SettingsLoader {
  SettingsLoader({Map<String, String>? environment})
      : _environment = environment ?? Platform.environment;

  final Map<String, String> _environment;

  /// Load settings from file path, returning empty settings if file doesn't exist
  Future<Settings> load(String? path) async {
    final settingsPath = path ?? _defaultSettingsPath;

    final file = File(settingsPath);
    if (!await file.exists()) {
      return Settings.empty();
    }

    final content = await file.readAsString();
    final substituted = _substituteEnvVars(content);

    final YamlMap yaml;
    try {
      final parsed = loadYaml(substituted);
      if (parsed == null) {
        return Settings.empty();
      }
      yaml = parsed as YamlMap;
    } on YamlException {
      rethrow;
    }

    return _parseSettings(yaml);
  }

  String get _defaultSettingsPath {
    final home = _environment['HOME'] ?? _environment['USERPROFILE'] ?? '';
    return '$home/.dartantic/settings.yaml';
  }

  /// Substitute ${VAR_NAME} patterns with environment variable values
  String _substituteEnvVars(String content) {
    return content.replaceAllMapped(
      RegExp(r'\$\{([^}]+)\}'),
      (match) {
        final varName = match.group(1)!;
        return _environment[varName] ?? '';
      },
    );
  }

  Settings _parseSettings(YamlMap yaml) {
    final agents = <String, AgentSettings>{};

    final agentsYaml = yaml['agents'] as YamlMap?;
    if (agentsYaml != null) {
      for (final entry in agentsYaml.entries) {
        final name = entry.key as String;
        final agentYaml = entry.value as YamlMap;
        agents[name] = _parseAgentSettings(agentYaml);
      }
    }

    return Settings(
      defaultAgent: yaml['default_agent'] as String?,
      thinking: yaml['thinking'] as bool?,
      serverTools: yaml['server_tools'] as bool? ?? true,
      chunkSize: yaml['chunk_size'] as int? ?? 512,
      chunkOverlap: yaml['chunk_overlap'] as int? ?? 100,
      agents: agents,
    );
  }

  AgentSettings _parseAgentSettings(YamlMap yaml) {
    final mcpServers = <McpServerSettings>[];
    final mcpServersYaml = yaml['mcp_servers'] as YamlList?;
    if (mcpServersYaml != null) {
      for (final serverYaml in mcpServersYaml) {
        mcpServers.add(_parseMcpServerSettings(serverYaml as YamlMap));
      }
    }

    final headersYaml = yaml['headers'] as YamlMap?;
    final headers = <String, String>{};
    if (headersYaml != null) {
      for (final entry in headersYaml.entries) {
        headers[entry.key as String] = entry.value as String;
      }
    }

    return AgentSettings(
      model: yaml['model'] as String,
      system: yaml['system'] as String?,
      thinking: yaml['thinking'] as bool?,
      serverTools: yaml['server_tools'] as bool?,
      outputSchema: _parseOutputSchema(yaml['output_schema']),
      apiKeyName: yaml['api_key_name'] as String?,
      baseUrl: yaml['base_url'] as String?,
      headers: headers,
      mcpServers: mcpServers,
    );
  }

  Map<String, Object?>? _parseOutputSchema(Object? schema) {
    if (schema == null) return null;
    if (schema is YamlMap) {
      return _yamlMapToMap(schema);
    }
    return null;
  }

  Map<String, Object?> _yamlMapToMap(YamlMap yaml) {
    final result = <String, Object?>{};
    for (final entry in yaml.entries) {
      final key = entry.key as String;
      final value = entry.value;
      if (value is YamlMap) {
        result[key] = _yamlMapToMap(value);
      } else if (value is YamlList) {
        result[key] = _yamlListToList(value);
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  List<Object?> _yamlListToList(YamlList yaml) {
    return yaml.map((item) {
      if (item is YamlMap) {
        return _yamlMapToMap(item);
      } else if (item is YamlList) {
        return _yamlListToList(item);
      }
      return item;
    }).toList();
  }

  McpServerSettings _parseMcpServerSettings(YamlMap yaml) {
    final headersYaml = yaml['headers'] as YamlMap?;
    final headers = <String, String>{};
    if (headersYaml != null) {
      for (final entry in headersYaml.entries) {
        headers[entry.key as String] = entry.value as String;
      }
    }

    final envYaml = yaml['environment'] as YamlMap?;
    final environment = <String, String>{};
    if (envYaml != null) {
      for (final entry in envYaml.entries) {
        environment[entry.key as String] = entry.value as String;
      }
    }

    final argsYaml = yaml['args'] as YamlList?;
    final args =
        argsYaml?.map((arg) => arg as String).toList() ?? <String>[];

    return McpServerSettings(
      name: yaml['name'] as String,
      url: yaml['url'] as String?,
      headers: headers,
      command: yaml['command'] as String?,
      args: args,
      environment: environment,
      workingDirectory: yaml['working_directory'] as String?,
    );
  }
}
