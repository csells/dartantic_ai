import 'dart:io';

import 'package:args/command_runner.dart';

import '../exit_codes.dart';
import '../settings/settings.dart';
import '../settings/settings_loader.dart';

/// Base class for all Dartantic CLI commands.
///
/// Provides access to global options and shared functionality.
abstract class DartanticCommand extends Command<int> {
  DartanticCommand(this._settingsLoader);

  final SettingsLoader _settingsLoader;

  // Global options accessed via globalResults
  String? get agent => globalResults?['agent'] as String?;
  String? get settingsPath => globalResults?['settings'] as String?;
  String? get workingDirectory => globalResults?['cwd'] as String?;
  String? get outputDirectory => globalResults?['output-dir'] as String?;
  bool get verbose => globalResults?['verbose'] as bool? ?? false;
  bool get noThinking => globalResults?['no-thinking'] as bool? ?? false;
  List<String> get noServerTools =>
      globalResults?['no-server-tool'] as List<String>? ?? [];
  bool get noColor => globalResults?['no-color'] as bool? ?? false;

  /// Load settings from the settings file.
  Future<Settings> loadSettings() async {
    return _settingsLoader.load(settingsPath);
  }

  /// Resolve agent name: CLI arg > env var > settings default > 'google'
  String resolveAgentName(Settings settings) {
    return agent ??
        Platform.environment['DARTANTIC_AGENT'] ??
        settings.defaultAgent ??
        'google';
  }

  /// Get the effective working directory.
  String getEffectiveWorkingDirectory() {
    return workingDirectory ?? Directory.current.path;
  }

  /// Validate that a directory exists.
  Future<bool> validateDirectory(String path, String name) async {
    if (!await Directory(path).exists()) {
      stderr.writeln('Error: $name not found: $path');
      return false;
    }
    return true;
  }

  /// Usage examples for this command. Override in subclasses.
  List<String> get examples => [];

  /// Build the full invocation path including parent commands.
  String get fullInvocation {
    final parts = <String>['dartantic'];
    Command<int>? current = this;
    final commandNames = <String>[];

    while (current != null) {
      if (current.name.isNotEmpty) {
        commandNames.insert(0, current.name);
      }
      current = current.parent;
    }

    parts.addAll(commandNames);
    return parts.join(' ');
  }

  /// Build the help output with command options, global options, and examples.
  @override
  String get usage {
    final buffer = StringBuffer()
      ..writeln(description)
      ..writeln()
      ..writeln('Usage: $fullInvocation [options]');

    // Command-specific options
    if (argParser.options.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Options:')
        ..writeln(argParser.usage);
    }

    // Global options from parent runner
    if (runner != null) {
      buffer
        ..writeln()
        ..writeln('Global Options:')
        ..writeln(runner!.argParser.usage);
    }

    // Examples
    if (examples.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Examples:');
      for (final example in examples) {
        buffer.writeln('  $example');
      }
    }

    return buffer.toString();
  }
}

/// Mixin for commands that require a prompt input.
mixin PromptCommandMixin on DartanticCommand {
  /// Read prompt from stdin if available.
  Future<String> readStdin() async {
    final buffer = StringBuffer();
    if (stdin.hasTerminal) {
      return '';
    }
    await for (final line in stdin.transform(const SystemEncoding().decoder)) {
      buffer.write(line);
    }
    return buffer.toString().trim();
  }

  /// Get the prompt from -p flag or stdin.
  Future<String?> getPrompt(String? promptArg) async {
    if (promptArg != null && promptArg.isNotEmpty) {
      return promptArg;
    }
    final stdinPrompt = await readStdin();
    if (stdinPrompt.isNotEmpty) {
      return stdinPrompt;
    }
    return null;
  }

  /// Report missing prompt error and return exit code.
  int reportMissingPrompt() {
    stderr.writeln(
      'Error: No prompt provided. Use -p or pipe input via stdin.',
    );
    return ExitCodes.invalidArguments;
  }
}
