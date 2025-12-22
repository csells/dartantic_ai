import 'dart:io';

import 'package:args/args.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:json_schema/json_schema.dart';

import '../exit_codes.dart';
import '../mcp/mcp_tool_collector.dart';
import '../prompt/prompt_processor.dart';
import '../settings/settings.dart';
import '../settings/settings_loader.dart';
import 'base_command.dart';
import 'utils.dart';

/// Command to send a chat prompt to an AI agent.
class ChatCommand extends DartanticCommand with PromptCommandMixin {
  ChatCommand(SettingsLoader settingsLoader) : super(settingsLoader) {
    argParser
      ..addOption(
        'prompt',
        abbr: 'p',
        help: 'Prompt text or @filename (.prompt files use dotprompt)',
      )
      ..addOption(
        'output-schema',
        help: 'Request structured JSON output (inline JSON or @file)',
      )
      ..addOption(
        'temperature',
        abbr: 't',
        help: 'Model temperature (0.0-1.0)',
      );
  }

  @override
  final String name = 'chat';

  @override
  final String description = 'Send a chat prompt to an AI agent (default command)';

  @override
  List<String> get examples => [
        'dartantic -p "What is 2+2?"',
        'dartantic chat -p "Hello" -a anthropic',
        'echo "Question" | dartantic',
        'dartantic -p @prompt.txt',
        r"dartantic -p @template.prompt name=Alice",
        "dartantic -p 'Summarize' --output-schema '{\"type\":\"object\"}'",
      ];

  @override
  String get usage {
    final buffer = StringBuffer()
      ..writeln(description)
      ..writeln()
      ..writeln('Usage: dartantic chat [options]')
      ..writeln('       dartantic [options]  (chat is the default command)')
      ..writeln()
      ..writeln('Options:')
      ..writeln(argParser.usage);

    if (runner != null) {
      buffer
        ..writeln()
        ..writeln('Global Options:')
        ..writeln(runner!.argParser.usage);
    }

    buffer
      ..writeln()
      ..writeln('Examples:');
    for (final example in examples) {
      buffer.writeln('  $example');
    }

    return buffer.toString();
  }

  /// Run with pre-parsed global results (for implicit chat invocation).
  ///
  /// This is called when the user runs `dartantic` with stdin but no -p flag.
  Future<int> runImplicit(ArgResults topLevelResults, Settings settings) async {
    // Store references for global option access
    _overrideGlobalResults = topLevelResults;
    _overrideArgResults = topLevelResults;
    _preloadedSettings = settings;
    return _executeChat();
  }

  /// Run with raw args for implicit chat (when -p flag is used without 'chat' command).
  ///
  /// This is called when the user runs `dartantic -p "hello"` without
  /// specifying the `chat` command explicitly.
  Future<int> runImplicitWithArgs(
    List<String> args,
    Settings settings,
    ArgParser globalParser,
  ) async {
    // Create a combined parser with both global and chat options
    final combinedParser = ArgParser()
      // Global options
      ..addOption('agent', abbr: 'a')
      ..addOption('settings', abbr: 's')
      ..addOption('cwd', abbr: 'd')
      ..addOption('output-dir', abbr: 'o')
      ..addFlag('verbose', abbr: 'v', negatable: false)
      ..addFlag('no-thinking', negatable: false)
      ..addMultiOption('no-server-tool')
      ..addFlag('no-color', negatable: false)
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('version', negatable: false)
      // Chat options
      ..addOption('prompt', abbr: 'p')
      ..addOption('output-schema')
      ..addOption('temperature', abbr: 't');

    final results = combinedParser.parse(args);

    _overrideGlobalResults = results;
    _overrideArgResults = results;
    _preloadedSettings = settings;
    return _executeChat();
  }

  ArgResults? _overrideGlobalResults;
  ArgResults? _overrideArgResults;
  Settings? _preloadedSettings;

  @override
  ArgResults? get globalResults => _overrideGlobalResults ?? super.globalResults;

  ArgResults get _argResults => _overrideArgResults ?? argResults!;

  @override
  Future<int> run() async {
    return _executeChat();
  }

  Future<int> _executeChat() async {
    final settings = _preloadedSettings ?? await loadSettings();

    // Determine agent name: CLI arg > env var > settings default > 'google'
    var agentName = resolveAgentName(settings);

    // Safely get prompt - may not exist in argResults for stdin-only usage
    var rawPrompt = _argResults.options.contains('prompt')
        ? _argResults['prompt'] as String?
        : null;

    // If no prompt provided, read from stdin
    if (rawPrompt == null || rawPrompt.isEmpty) {
      rawPrompt = await readStdin();
      if (rawPrompt.isEmpty) {
        return reportMissingPrompt();
      }
    }

    // Get working directory and validate it exists
    final cwd = workingDirectory;
    if (cwd != null && !await validateDirectory(cwd, 'Working directory')) {
      return ExitCodes.invalidArguments;
    }

    // Process prompt (handle @files, .prompt files, etc.)
    final promptProcessor = PromptProcessor(workingDirectory: cwd);

    // Extract template variables from rest args (key=value format)
    final restArgs = _argResults.rest;
    final templateVariables = restArgs
        .where((arg) => arg.contains('=') && !arg.startsWith('-'))
        .toList();

    final processed = await promptProcessor.process(
      rawPrompt,
      templateVariables: templateVariables,
    );

    // Check for prompt processing errors (file not found, etc.)
    if (!processed.isSuccess) {
      stderr.writeln('Error: ${processed.error}');
      return ExitCodes.invalidArguments;
    }

    // .prompt file model override takes precedence over settings default
    // but CLI -a flag still takes highest precedence
    if (processed.modelOverride != null && agent == null) {
      agentName = processed.modelOverride!;
    }

    // Resolve agent: look up in settings, otherwise pass directly to Agent
    final agentSettings = settings.agents[agentName];
    final modelString = agentSettings?.model ?? agentName;
    final systemPrompt = agentSettings?.system;

    // Determine thinking setting: CLI --no-thinking overrides settings
    // Default to false since not all providers support thinking
    final enableThinking = noThinking
        ? false
        : (agentSettings?.thinking ?? settings.thinking ?? false);

    // Parse temperature if provided
    // Safely get temperature - may not exist in argResults for stdin-only usage
    final temperatureStr = _argResults.options.contains('temperature')
        ? _argResults['temperature'] as String?
        : null;
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
    // Safely get output-schema - may not exist in argResults for stdin-only usage
    final outputSchemaStr = _argResults.options.contains('output-schema')
        ? _argResults['output-schema'] as String?
        : null;
    JsonSchema? outputSchema;
    if (outputSchemaStr != null) {
      try {
        final schemaResult = await parseOutputSchema(outputSchemaStr);
        if (schemaResult.error != null) {
          stderr.writeln('Error: Invalid output schema: ${schemaResult.error}');
          return ExitCodes.invalidArguments;
        }
        outputSchema = schemaResult.schema;
      } on FormatException catch (e) {
        stderr.writeln('Error: Invalid output schema JSON: ${e.message}');
        return ExitCodes.invalidArguments;
      }
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
    final disabledTools = <String>{};
    for (final entry in noServerTools) {
      // Support comma-separated list
      disabledTools.addAll(entry.split(',').map((s) => s.trim()));
    }

    if (disabledTools.isNotEmpty) {
      tools = tools.where((t) => !disabledTools.contains(t.name)).toList();
    }

    // Create agent with tools
    final agentInstance = Agent(
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
    await for (final chunk in agentInstance.sendStream(
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
}
