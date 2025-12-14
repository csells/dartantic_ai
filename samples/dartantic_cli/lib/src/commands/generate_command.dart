import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../exit_codes.dart';
import '../prompt/prompt_processor.dart';
import '../settings/settings_loader.dart';
import 'base_command.dart';
import 'utils.dart';

/// Command to generate media content.
class GenerateCommand extends DartanticCommand with PromptCommandMixin {
  GenerateCommand(SettingsLoader settingsLoader) : super(settingsLoader) {
    argParser
      ..addOption(
        'prompt',
        abbr: 'p',
        help: 'Prompt text or @filename',
      )
      ..addMultiOption(
        'mime',
        help: 'MIME type to generate (required, repeatable)',
      );
  }

  @override
  final String name = 'generate';

  @override
  final String description = 'Generate media content (images, PDFs, etc.)';

  @override
  List<String> get examples => [
        'dartantic generate -p "A sunset over mountains" --mime image/png',
        'dartantic generate -p @prompt.txt --mime image/jpeg --mime image/png',
        'echo "A cat" | dartantic generate --mime image/webp',
      ];

  @override
  Future<int> run() async {
    // Parse --mime (required for generate command)
    final mimeTypes = argResults!['mime'] as List<String>;
    if (mimeTypes.isEmpty) {
      stderr.writeln('Error: --mime is required for generate command');
      return ExitCodes.invalidArguments;
    }

    final settings = await loadSettings();
    final agentName = resolveAgentName(settings);

    // Get prompt
    final rawPrompt = await getPrompt(argResults!['prompt'] as String?);
    if (rawPrompt == null) {
      return reportMissingPrompt();
    }

    // Get working directory and validate it exists
    final cwd = workingDirectory;
    if (cwd != null && !await validateDirectory(cwd, 'Working directory')) {
      return ExitCodes.invalidArguments;
    }

    // Process prompt (handle @files, etc.)
    final promptProcessor = PromptProcessor(workingDirectory: cwd);
    final processed = await promptProcessor.process(rawPrompt);

    // Check for prompt processing errors (file not found, etc.)
    if (!processed.isSuccess) {
      stderr.writeln('Error: ${processed.error}');
      return ExitCodes.invalidArguments;
    }

    // Resolve agent: look up in settings, otherwise pass directly to Agent
    final agentSettings = settings.agents[agentName];
    final modelString = agentSettings?.model ?? agentName;

    // Create agent
    final agent = Agent(modelString);

    // Get output directory
    final outputDir = outputDirectory ?? '.';

    // Ensure output directory exists
    final outputDirObj = Directory(outputDir);
    if (!await outputDirObj.exists()) {
      await outputDirObj.create(recursive: true);
    }

    // Call generateMedia
    final result = await agent.generateMedia(
      processed.prompt,
      mimeTypes: mimeTypes,
      attachments: processed.attachments,
    );

    // Write assets to output directory
    var assetCount = 0;
    for (final asset in result.assets) {
      if (asset is DataPart) {
        final filename = asset.name ?? generateFilename(asset.mimeType);
        final file = File('$outputDir/$filename');
        await file.writeAsBytes(asset.bytes);
        stdout.writeln('Generated: ${file.path}');
        assetCount++;
      } else if (asset is LinkPart) {
        stdout.writeln('Link: ${asset.url}');
        assetCount++;
      }
    }

    // Also handle any links
    for (final link in result.links) {
      stdout.writeln('Link: ${link.url}');
      assetCount++;
    }

    if (assetCount == 0) {
      stderr.writeln('Warning: No assets were generated');
    }

    return ExitCodes.success;
  }
}
