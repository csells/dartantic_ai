import 'package:args/command_runner.dart';

import '../settings/settings_loader.dart';
import 'embed_create_command.dart';
import 'embed_search_command.dart';

/// Parent command for embedding operations.
///
/// This command delegates to subcommands: `create` and `search`.
class EmbedCommand extends Command<int> {
  EmbedCommand(SettingsLoader settingsLoader) {
    addSubcommand(EmbedCreateCommand(settingsLoader));
    addSubcommand(EmbedSearchCommand(settingsLoader));
  }

  @override
  final String name = 'embed';

  @override
  final String description = 'Embedding operations (create, search)';

  @override
  String get invocation => '$name <subcommand>';
}
