import '../exit_codes.dart';
import '../repl/repl_session.dart';
import '../settings/settings_loader.dart';
import 'base_command.dart';

/// Command to start an interactive REPL session.
class ReplCommand extends DartanticCommand {
  ReplCommand(SettingsLoader settingsLoader) : super(settingsLoader);

  @override
  final String name = 'repl';

  @override
  final String description = 'Start an interactive chat session';

  @override
  List<String> get examples => [
        'dartantic repl',
        'dartantic repl -a coder',
        'dartantic repl -a anthropic --no-thinking',
      ];

  @override
  Future<int> run() async {
    final settings = await loadSettings();

    // Resolve agent name
    final agentName = resolveAgentName(settings);

    // Validate working directory if provided
    final cwd = workingDirectory;
    if (cwd != null && !await validateDirectory(cwd, 'Working directory')) {
      return ExitCodes.invalidArguments;
    }

    // Determine thinking setting: CLI --no-thinking overrides settings
    final enableThinking = noThinking
        ? false
        : (settings.agents[agentName]?.thinking ?? settings.thinking);

    // Create and run REPL session
    final session = ReplSession(
      settings: settings,
      initialAgentName: agentName,
      noColor: noColor,
      workingDirectory: cwd,
      verbose: verbose,
      enableThinking: enableThinking,
    );

    return session.run();
  }
}
