import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:json_schema/json_schema.dart';
import 'package:yaml/yaml.dart';

import 'mcp/mcp_tool_collector.dart';
import 'prompt/prompt_processor.dart';
import 'settings/settings.dart';
import 'settings/settings_loader.dart';

/// Exit codes per CLI specification
abstract final class ExitCodes {
  static const int success = 0;
  static const int generalError = 1;
  static const int invalidArguments = 2;
  static const int configurationError = 3;
  static const int apiError = 4;
  static const int networkError = 5;
}

/// Main command runner for the Dartantic CLI
class DartanticCommandRunner {
  DartanticCommandRunner({Map<String, String>? environment})
      : _settingsLoader = SettingsLoader(environment: environment);

  final SettingsLoader _settingsLoader;

  final ArgParser _argParser = ArgParser()
    // Global options
    ..addOption(
      'agent',
      abbr: 'a',
      help: 'Agent name or model string (default: google)',
    )
    ..addOption(
      'settings',
      abbr: 's',
      help: 'Settings file (default: ~/.dartantic/settings.yaml)',
    )
    ..addOption(
      'cwd',
      abbr: 'd',
      help: 'Working directory (default: shell cwd)',
    )
    ..addOption(
      'output-dir',
      abbr: 'o',
      help: 'Output directory for generated files (default: cwd)',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Enable verbose output (shows token usage)',
      negatable: false,
    )
    ..addFlag(
      'no-thinking',
      help: 'Disable extended thinking',
      negatable: false,
    )
    ..addMultiOption(
      'no-server-tool',
      help: 'Disable server-side tools (comma-separated)',
    )
    ..addFlag(
      'no-color',
      help: 'Disable colored output',
      negatable: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show help',
      negatable: false,
    )
    ..addFlag(
      'version',
      help: 'Show version',
      negatable: false,
    )
    // Chat command options
    ..addOption(
      'prompt',
      abbr: 'p',
      help: 'Prompt text or @filename (.prompt files use dotprompt)',
    )
    ..addOption(
      'output-schema',
      help: 'Request structured JSON output',
    )
    ..addOption(
      'temperature',
      abbr: 't',
      help: 'Model temperature (0.0-1.0)',
    );

  Future<int> run(List<String> args) async {
    final ArgResults results;
    try {
      results = _argParser.parse(args);
    } on FormatException catch (e) {
      stderr.writeln('Error: ${e.message}');
      stderr.writeln();
      _printUsage();
      return ExitCodes.invalidArguments;
    }

    if (results['help'] as bool) {
      _printUsage();
      return ExitCodes.success;
    }

    if (results['version'] as bool) {
      stdout.writeln('dartantic_cli version 1.0.0');
      return ExitCodes.success;
    }

    // Load settings file
    final Settings settings;
    try {
      settings = await _settingsLoader.load(results['settings'] as String?);
    } on YamlException catch (e) {
      stderr.writeln('Error: Invalid settings file: ${e.message}');
      return ExitCodes.configurationError;
    }

    // Check for subcommand in rest args
    final rest = results.rest;
    if (rest.isNotEmpty) {
      final command = rest.first;
      switch (command) {
        case 'chat':
          return _runChat(results, settings);
        case 'generate':
          stderr.writeln('Error: generate command not yet implemented');
          return ExitCodes.generalError;
        case 'embed':
          stderr.writeln('Error: embed command not yet implemented');
          return ExitCodes.generalError;
        case 'models':
          stderr.writeln('Error: models command not yet implemented');
          return ExitCodes.generalError;
        default:
          // Not a command, treat as part of prompt or error
          break;
      }
    }

    // Default to chat command
    return _runChat(results, settings);
  }

  Future<int> _runChat(ArgResults results, Settings settings) async {
    // Determine agent name: CLI arg > env var > settings default > 'google'
    var agentName = results['agent'] as String? ??
        Platform.environment['DARTANTIC_AGENT'] ??
        settings.defaultAgent ??
        'google';

    var rawPrompt = results['prompt'] as String?;

    // If no prompt provided, read from stdin
    if (rawPrompt == null || rawPrompt.isEmpty) {
      rawPrompt = await _readStdin();
      if (rawPrompt.isEmpty) {
        stderr.writeln(
          'Error: No prompt provided. Use -p or pipe input via stdin.',
        );
        return ExitCodes.invalidArguments;
      }
    }

    // Get working directory
    final workingDirectory = results['cwd'] as String?;

    // Process prompt (handle @files, .prompt files, etc.)
    final promptProcessor = PromptProcessor(workingDirectory: workingDirectory);

    // Extract template variables from rest args (key=value format)
    final templateVariables = results.rest
        .where((arg) => arg.contains('=') && !arg.startsWith('-'))
        .toList();

    final processed = await promptProcessor.process(
      rawPrompt,
      templateVariables: templateVariables,
    );

    // .prompt file model override takes precedence over settings default
    // but CLI -a flag still takes highest precedence
    if (processed.modelOverride != null && results['agent'] == null) {
      agentName = processed.modelOverride!;
    }

    // Resolve agent: look up in settings, otherwise pass directly to Agent
    final agentSettings = settings.agents[agentName];
    final modelString = agentSettings?.model ?? agentName;
    final systemPrompt = agentSettings?.system;

    // Determine thinking setting: CLI --no-thinking overrides settings
    // Default to false since not all providers support thinking
    final noThinking = results['no-thinking'] as bool;
    final enableThinking = noThinking
        ? false
        : (agentSettings?.thinking ?? settings.thinking ?? false);

    // Get output options
    final verbose = results['verbose'] as bool;
    final noColor = results['no-color'] as bool;

    // Parse temperature if provided
    final temperatureStr = results['temperature'] as String?;
    double? temperature;
    if (temperatureStr != null) {
      temperature = double.tryParse(temperatureStr);
      if (temperature == null || temperature < 0 || temperature > 1) {
        stderr.writeln(
          'Error: Invalid temperature "$temperatureStr". Must be between 0.0 and 1.0.',
        );
        return ExitCodes.invalidArguments;
      }
    }

    // Parse output schema if provided
    final outputSchemaStr = results['output-schema'] as String?;
    JsonSchema? outputSchema;
    if (outputSchemaStr != null) {
      final schemaResult = await _parseOutputSchema(outputSchemaStr);
      if (schemaResult.error != null) {
        stderr.writeln('Error: Invalid output schema: ${schemaResult.error}');
        return ExitCodes.invalidArguments;
      }
      outputSchema = schemaResult.schema;
    } else if (agentSettings?.outputSchema != null) {
      // Use output schema from agent settings
      outputSchema = JsonSchema.create(agentSettings!.outputSchema!);
    }

    // Collect MCP tools if configured
    final mcpToolCollector = McpToolCollector();
    var tools = <Tool>[];

    if (agentSettings?.mcpServers.isNotEmpty ?? false) {
      tools = await mcpToolCollector.collectTools(agentSettings!.mcpServers);
    }

    // Parse --no-server-tool flag and filter out disabled tools
    final noServerTools = results['no-server-tool'] as List<String>;
    final disabledTools = <String>{};
    for (final entry in noServerTools) {
      // Support comma-separated list
      disabledTools.addAll(entry.split(',').map((s) => s.trim()));
    }

    if (disabledTools.isNotEmpty) {
      tools = tools.where((t) => !disabledTools.contains(t.name)).toList();
    }

    // Create agent with tools
    final agent = Agent(
      modelString,
      tools: tools.isNotEmpty ? tools : null,
      enableThinking: enableThinking,
      temperature: temperature,
    );

    // Build history with system prompt if specified
    final history = <ChatMessage>[
      if (systemPrompt != null) ChatMessage.system(systemPrompt),
    ];

    // Track state for streaming output
    var inThinkingMode = false;
    LanguageModelUsage? lastUsage;

    // Stream the response
    await for (final chunk in agent.sendStream(
      processed.prompt,
      history: history,
      attachments: processed.attachments,
      outputSchema: outputSchema,
    )) {
      // Handle thinking output
      if (chunk.thinking != null && chunk.thinking!.isNotEmpty) {
        if (!inThinkingMode) {
          inThinkingMode = true;
          if (noColor) {
            stdout.write('[Thinking]\n');
          } else {
            // Dim/gray color for thinking
            stdout.write('\x1b[2m[Thinking]\n');
          }
        }
        stdout.write(chunk.thinking);
      }

      // Handle regular output
      if (chunk.output.isNotEmpty) {
        if (inThinkingMode) {
          inThinkingMode = false;
          if (noColor) {
            stdout.write('\n[/Thinking]\n\n');
          } else {
            // Reset color and end thinking section
            stdout.write('\n[/Thinking]\x1b[0m\n\n');
          }
        }
        stdout.write(chunk.output);
      }

      // Track usage for verbose output
      if (chunk.usage != null) {
        lastUsage = chunk.usage;
      }
    }
    stdout.writeln();

    // Output usage stats if verbose
    if (verbose && lastUsage != null) {
      final usageInfo = StringBuffer();
      if (lastUsage.promptTokens != null) {
        usageInfo.write('Input: ${lastUsage.promptTokens} tokens');
      }
      if (lastUsage.responseTokens != null) {
        if (usageInfo.isNotEmpty) usageInfo.write(', ');
        usageInfo.write('Output: ${lastUsage.responseTokens} tokens');
      }
      if (lastUsage.totalTokens != null) {
        if (usageInfo.isNotEmpty) usageInfo.write(', ');
        usageInfo.write('Total: ${lastUsage.totalTokens} tokens');
      }

      if (usageInfo.isNotEmpty) {
        if (noColor) {
          stderr.writeln('Usage: $usageInfo');
        } else {
          // Dim color for usage
          stderr.writeln('\x1b[2mUsage: $usageInfo\x1b[0m');
        }
      }
    }

    // Clean up MCP clients
    mcpToolCollector.dispose();

    return ExitCodes.success;
  }

  Future<String> _readStdin() async {
    final buffer = StringBuffer();
    // Check if stdin has data available
    if (stdin.hasTerminal) {
      // Interactive terminal - no piped input
      return '';
    }
    await for (final line in stdin.transform(const SystemEncoding().decoder)) {
      buffer.write(line);
    }
    return buffer.toString().trim();
  }

  void _printUsage() {
    stdout.writeln('dartantic - AI-powered CLI using the Dartantic framework');
    stdout.writeln();
    stdout.writeln('USAGE:');
    stdout.writeln('  dartantic [options]');
    stdout.writeln('  dartantic <command> [options]');
    stdout.writeln();
    stdout.writeln('COMMANDS:');
    stdout.writeln('  chat        Send a chat prompt (default command)');
    stdout.writeln('  generate    Generate media content');
    stdout.writeln('  embed       Embedding operations (create, search)');
    stdout.writeln('  models      List available models for a provider');
    stdout.writeln();
    stdout.writeln('OPTIONS:');
    stdout.writeln(_argParser.usage);
  }

  /// Parse output schema from string (inline JSON or @file reference)
  Future<_SchemaParseResult> _parseOutputSchema(String schemaStr) async {
    String jsonStr;

    // Check if it's a file reference
    if (schemaStr.startsWith('@')) {
      final filePath = schemaStr.substring(1);
      final file = File(filePath);
      if (!await file.exists()) {
        return _SchemaParseResult(error: 'Schema file not found: $filePath');
      }
      jsonStr = await file.readAsString();
    } else {
      jsonStr = schemaStr;
    }

    // Parse the JSON
    try {
      final schemaMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      return _SchemaParseResult(schema: JsonSchema.create(schemaMap));
    } on FormatException catch (e) {
      return _SchemaParseResult(error: 'Invalid JSON: ${e.message}');
    }
  }
}

/// Result of parsing an output schema
class _SchemaParseResult {
  _SchemaParseResult({this.schema, this.error});

  final JsonSchema? schema;
  final String? error;
}
