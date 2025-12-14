import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:yaml/yaml.dart';

import 'commands/chat_command.dart';
import 'commands/embed_command.dart';
import 'commands/generate_command.dart';
import 'commands/models_command.dart';
import 'exit_codes.dart';
import 'settings/settings.dart';
import 'settings/settings_loader.dart';

export 'exit_codes.dart';

/// Main command runner for the Dartantic CLI.
class DartanticCommandRunner extends CommandRunner<int> {
  DartanticCommandRunner({Map<String, String>? environment})
      : _settingsLoader = SettingsLoader(environment: environment),
        super('dartantic', 'AI-powered CLI using the Dartantic framework') {
    // Global options
    argParser
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
        'version',
        help: 'Show version',
        negatable: false,
      );

    // Add commands
    addCommand(ChatCommand(_settingsLoader));
    addCommand(GenerateCommand(_settingsLoader));
    addCommand(EmbedCommand(_settingsLoader));
    addCommand(ModelsCommand(_settingsLoader));
  }

  final SettingsLoader _settingsLoader;

  @override
  Future<int> run(Iterable<String> args) async {
    final argsList = args.toList();

    final ArgResults topLevelResults;
    try {
      topLevelResults = parse(argsList);
    } on FormatException catch (e) {
      // Check if the error is due to chat-specific options (implicit chat)
      if (_isChatOptionError(e.message, argsList)) {
        return _runImplicitChat(argsList);
      }
      stderr.writeln('Error: ${e.message}');
      stderr.writeln();
      printUsage();
      return ExitCodes.invalidArguments;
    } on UsageException catch (e) {
      // Check if the error is due to chat-specific options (implicit chat)
      if (_isChatOptionError(e.message, argsList)) {
        return _runImplicitChat(argsList);
      }
      stderr.writeln('Error: ${e.message}');
      stderr.writeln();
      printUsage();
      return ExitCodes.invalidArguments;
    }

    // Handle --help at the top level
    if (topLevelResults.wasParsed('help')) {
      printUsage();
      return ExitCodes.success;
    }

    final result = await runCommand(topLevelResults);
    return result ?? ExitCodes.success;
  }

  /// Check if the parse error is due to a chat-specific option.
  bool _isChatOptionError(String message, List<String> args) {
    const chatOptions = ['-p', '--prompt', '-t', '--temperature', '--output-schema'];
    return chatOptions.any((opt) => message.contains('"$opt"') || args.contains(opt));
  }

  /// Run implicit chat command with full arg parsing.
  Future<int> _runImplicitChat(List<String> args) async {
    // Load settings
    final settings = await _loadSettings(_parseGlobalOnly(args));
    if (settings == null) {
      return ExitCodes.configurationError;
    }

    final chatCommand = ChatCommand(_settingsLoader);
    return chatCommand.runImplicitWithArgs(args, settings, argParser);
  }

  /// Parse only global options, ignoring unknown options.
  ArgResults _parseGlobalOnly(List<String> args) {
    // Create a parser that allows unknown options to pass through
    final globalParser = ArgParser(allowTrailingOptions: true)
      ..addOption('agent', abbr: 'a')
      ..addOption('settings', abbr: 's')
      ..addOption('cwd', abbr: 'd')
      ..addOption('output-dir', abbr: 'o')
      ..addFlag('verbose', abbr: 'v', negatable: false)
      ..addFlag('no-thinking', negatable: false)
      ..addMultiOption('no-server-tool')
      ..addFlag('no-color', negatable: false)
      ..addFlag('help', abbr: 'h', negatable: false)
      ..addFlag('version', negatable: false);

    // Filter to only global args
    final globalArgs = <String>[];
    var i = 0;
    while (i < args.length) {
      final arg = args[i];
      if (arg == '-s' || arg == '--settings' ||
          arg == '-a' || arg == '--agent' ||
          arg == '-d' || arg == '--cwd' ||
          arg == '-o' || arg == '--output-dir') {
        globalArgs.add(arg);
        if (i + 1 < args.length) {
          globalArgs.add(args[i + 1]);
          i += 2;
        } else {
          i++;
        }
      } else if (arg == '-v' || arg == '--verbose' ||
                 arg == '--no-thinking' || arg == '--no-color' ||
                 arg == '-h' || arg == '--help' || arg == '--version') {
        globalArgs.add(arg);
        i++;
      } else if (arg.startsWith('--no-server-tool')) {
        globalArgs.add(arg);
        i++;
      } else {
        i++;
      }
    }

    return globalParser.parse(globalArgs);
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    // Handle --version
    if (topLevelResults['version'] as bool) {
      stdout.writeln('dartantic_cli version 1.0.0');
      return ExitCodes.success;
    }

    // Handle --help at top level (no command specified)
    if (topLevelResults.command == null &&
        topLevelResults.wasParsed('help')) {
      printUsage();
      return ExitCodes.success;
    }

    // Handle --help for commands (check recursively through subcommands)
    if (topLevelResults.command != null) {
      var cmdResults = topLevelResults.command;
      var command = commands[cmdResults!.name];

      // Walk down to the deepest subcommand
      while (cmdResults!.command != null) {
        final subName = cmdResults.command!.name;
        command = command!.subcommands[subName];
        cmdResults = cmdResults.command;
      }

      // Check if --help was requested for this command
      if (cmdResults.wasParsed('help')) {
        stdout.writeln(command!.usage);
        return ExitCodes.success;
      }

      // Validate rest args - reject anything that looks like a flag
      // This catches cases like `models list -a openai` where -a should be global
      final unexpectedFlags = cmdResults.rest
          .where((arg) => arg.startsWith('-'))
          .toList();
      if (unexpectedFlags.isNotEmpty) {
        final flagList = unexpectedFlags.join(', ');
        stderr.writeln('Error: Unknown option(s) for "${cmdResults.name}": $flagList');
        stderr.writeln();
        stderr.writeln('Note: Global options like -a/--agent must come BEFORE the command name.');
        stderr.writeln('Example: dartantic -a openai ${cmdResults.name}');
        stderr.writeln();
        stderr.writeln('Run "dartantic ${cmdResults.name} --help" for usage information.');
        return ExitCodes.invalidArguments;
      }
    }

    // Load settings early (needed for implicit chat)
    final settings = await _loadSettings(topLevelResults);
    if (settings == null) {
      return ExitCodes.configurationError;
    }

    // If no command specified, route to chat command (backwards compatibility)
    // This handles: dartantic (with stdin) without -p
    if (topLevelResults.command == null) {
      final chatCommand = ChatCommand(_settingsLoader);
      return chatCommand.runImplicit(topLevelResults, settings);
    }

    // Run the specified command
    return super.runCommand(topLevelResults);
  }

  /// Load settings from file with error handling.
  Future<Settings?> _loadSettings(ArgResults results) async {
    try {
      return await _settingsLoader.load(results['settings'] as String?);
    } on YamlException catch (e) {
      stderr.writeln('Error: Invalid settings file: ${e.message}');
      return null;
    }
  }

  @override
  void printUsage() {
    stdout.writeln(usage);
  }

  @override
  String get usage {
    final buffer = StringBuffer()
      ..writeln(description)
      ..writeln()
      ..writeln('Usage: dartantic [options]')
      ..writeln('       dartantic <command> [options]')
      ..writeln()
      ..writeln('Commands:');

    // List commands with descriptions
    for (final command in commands.values) {
      final name = command.name.padRight(12);
      buffer.writeln('  $name${command.description}');
    }

    buffer
      ..writeln()
      ..writeln('Global Options:')
      ..writeln(argParser.usage)
      ..writeln()
      ..writeln('Run "dartantic help <command>" for more information about a command.')
      ..writeln()
      ..writeln('Examples:')
      ..writeln('  dartantic -p "What is 2+2?"')
      ..writeln('  dartantic chat -a anthropic -p "Hello"')
      ..writeln('  dartantic -a openai models')
      ..writeln('  dartantic embed create doc.txt > embeddings.json');

    return buffer.toString();
  }
}
