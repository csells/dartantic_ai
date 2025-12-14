import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../embeddings/chunker.dart';
import '../exit_codes.dart';
import '../settings/settings_loader.dart';
import 'base_command.dart';

/// Command to create embeddings from text files.
class EmbedCreateCommand extends DartanticCommand {
  EmbedCreateCommand(SettingsLoader settingsLoader) : super(settingsLoader) {
    argParser
      ..addOption(
        'chunk-size',
        help: 'Chunk size in characters (default: 512)',
      )
      ..addOption(
        'chunk-overlap',
        help: 'Chunk overlap in characters (default: 100)',
      );
  }

  @override
  final String name = 'create';

  @override
  final String description = 'Create embeddings from text files';

  @override
  String get invocation => '$name <files...>';

  @override
  List<String> get examples => [
        'dartantic embed create doc.txt',
        'dartantic embed create *.txt > embeddings.json',
        'dartantic -a openai embed create --chunk-size 256 doc.txt',
      ];

  @override
  Future<int> run() async {
    final files = argResults!.rest;
    if (files.isEmpty) {
      stderr.writeln('Error: No files provided for embed create');
      stderr.writeln('Usage: dartantic embed create <files...>');
      return ExitCodes.invalidArguments;
    }

    final settings = await loadSettings();
    final agentName = resolveAgentName(settings);

    // Resolve agent
    final agentSettings = settings.agents[agentName];
    final modelString = agentSettings?.model ?? agentName;

    // Parse chunk options
    final chunkSizeStr = argResults!['chunk-size'] as String?;
    final chunkOverlapStr = argResults!['chunk-overlap'] as String?;

    final chunkSize = chunkSizeStr != null
        ? int.tryParse(chunkSizeStr) ?? settings.chunkSize
        : settings.chunkSize;
    final chunkOverlap = chunkOverlapStr != null
        ? int.tryParse(chunkOverlapStr) ?? settings.chunkOverlap
        : settings.chunkOverlap;

    final chunker = TextChunker(chunkSize: chunkSize, overlap: chunkOverlap);

    // Create agent
    final agent = Agent(modelString);

    // Process each file
    final documents = <Map<String, dynamic>>[];
    final allChunks = <String>[];
    final chunkMeta = <({String file, int offset})>[];

    // Get working directory
    final cwd = getEffectiveWorkingDirectory();

    for (final filePath in files) {
      final resolvedPath =
          filePath.startsWith('/') ? filePath : '$cwd/$filePath';
      final file = File(resolvedPath);

      if (!await file.exists()) {
        stderr.writeln('Error: File not found: $filePath');
        return ExitCodes.invalidArguments;
      }

      final content = await file.readAsString();
      final chunks = chunker.chunk(content);

      for (final chunk in chunks) {
        allChunks.add(chunk.text);
        chunkMeta.add((file: filePath, offset: chunk.offset));
      }
    }

    if (allChunks.isEmpty) {
      stderr.writeln('Error: No content to embed (files may be empty)');
      return ExitCodes.invalidArguments;
    }

    // Embed all chunks
    final batchResult = await agent.embedDocuments(allChunks);
    final embeddings = batchResult.embeddings;

    // Build output structure
    final fileChunks = <String, List<Map<String, dynamic>>>{};
    for (var i = 0; i < allChunks.length; i++) {
      final meta = chunkMeta[i];
      fileChunks.putIfAbsent(meta.file, () => []);
      fileChunks[meta.file]!.add({
        'text': allChunks[i],
        'vector': embeddings[i],
        'offset': meta.offset,
      });
    }

    for (final entry in fileChunks.entries) {
      documents.add({
        'file': entry.key,
        'chunks': entry.value,
      });
    }

    final output = {
      'model': modelString,
      'created': DateTime.now().toUtc().toIso8601String(),
      'chunk_size': chunkSize,
      'chunk_overlap': chunkOverlap,
      'documents': documents,
    };

    // Output JSON to stdout
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));

    return ExitCodes.success;
  }
}
