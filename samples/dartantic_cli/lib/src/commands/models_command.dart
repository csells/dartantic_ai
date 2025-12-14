import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../exit_codes.dart';
import '../settings/settings_loader.dart';
import 'base_command.dart';

/// Command to list available models for a provider.
class ModelsCommand extends DartanticCommand {
  ModelsCommand(SettingsLoader settingsLoader) : super(settingsLoader);

  @override
  final String name = 'models';

  @override
  final String description = 'List available models for a provider';

  @override
  List<String> get examples => [
        'dartantic models',
        'dartantic -a openai models',
        'dartantic -a anthropic models',
      ];

  @override
  Future<int> run() async {
    // Models command doesn't accept positional arguments
    // This catches typos like "models list-a openai" instead of "models -a openai"
    if (argResults!.rest.isNotEmpty) {
      stderr.writeln('Error: Unexpected arguments: ${argResults!.rest.join(' ')}');
      stderr.writeln();
      stderr.writeln('The models command does not accept positional arguments.');
      stderr.writeln('To specify a provider, use the -a flag:');
      stderr.writeln('  dartantic -a openai models');
      stderr.writeln('  dartantic models -a anthropic');
      stderr.writeln();
      stderr.writeln('Run "dartantic models --help" for more information.');
      return ExitCodes.invalidArguments;
    }

    final settings = await loadSettings();

    // Use global -a option to determine provider
    final agentName = resolveAgentName(settings);

    // Resolve to provider (via settings lookup or direct)
    final agentSettings = settings.agents[agentName];
    final modelString = agentSettings?.model ?? agentName;

    // Extract provider name from model string (before : or /)
    final parsed = ModelStringParser.parse(modelString);
    final providerName = parsed.providerName;

    // Get provider instance
    final provider = Agent.getProvider(providerName);

    // List models
    final models = await provider.listModels().toList();

    // Group by kind for display
    final chatModels =
        models.where((m) => m.kinds.contains(ModelKind.chat)).toList();
    final embeddingsModels =
        models.where((m) => m.kinds.contains(ModelKind.embeddings)).toList();
    final mediaModels =
        models.where((m) => m.kinds.contains(ModelKind.media)).toList();
    final otherModels = models
        .where(
          (m) =>
              !m.kinds.contains(ModelKind.chat) &&
              !m.kinds.contains(ModelKind.embeddings) &&
              !m.kinds.contains(ModelKind.media),
        )
        .toList();

    // Output formatted list
    stdout.writeln('Provider: ${provider.displayName} (${provider.name})');
    stdout.writeln('');

    if (chatModels.isNotEmpty) {
      stdout.writeln('Chat Models:');
      for (final m in chatModels) {
        stdout.writeln('  ${m.name}');
      }
      stdout.writeln('');
    }

    if (embeddingsModels.isNotEmpty) {
      stdout.writeln('Embeddings Models:');
      for (final m in embeddingsModels) {
        stdout.writeln('  ${m.name}');
      }
      stdout.writeln('');
    }

    if (mediaModels.isNotEmpty) {
      stdout.writeln('Media Models:');
      for (final m in mediaModels) {
        stdout.writeln('  ${m.name}');
      }
      stdout.writeln('');
    }

    if (otherModels.isNotEmpty) {
      stdout.writeln('Other Models:');
      for (final m in otherModels) {
        stdout.writeln('  ${m.name}');
      }
      stdout.writeln('');
    }

    if (models.isEmpty) {
      stdout.writeln('No models available.');
    }

    return ExitCodes.success;
  }
}
