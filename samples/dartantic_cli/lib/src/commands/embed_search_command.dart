import 'dart:convert';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

import '../exit_codes.dart';
import '../settings/settings_loader.dart';
import 'base_command.dart';

/// Command to search embeddings with a query.
class EmbedSearchCommand extends DartanticCommand {
  EmbedSearchCommand(SettingsLoader settingsLoader) : super(settingsLoader) {
    argParser.addOption(
      'query',
      abbr: 'q',
      help: 'Search query (required)',
    );
  }

  @override
  final String name = 'search';

  @override
  final String description = 'Search embeddings with a query';

  @override
  String get invocation => '$name -q <query> <embeddings.json>';

  @override
  List<String> get examples => [
        'dartantic embed search -q "how to install" embeddings.json',
        'dartantic embed search -q "API usage" ./embeddings/',
        'dartantic -a openai embed search -q "auth" docs.json',
      ];

  @override
  Future<int> run() async {
    // Require -q query
    final query = argResults!['query'] as String?;
    if (query == null || query.isEmpty) {
      stderr.writeln('Error: -q/--query is required for embed search');
      stderr.writeln('Usage: dartantic embed search -q <query> <embeddings.json>');
      return ExitCodes.invalidArguments;
    }

    final files = argResults!.rest;
    if (files.isEmpty) {
      stderr.writeln('Error: No embeddings file provided');
      stderr.writeln('Usage: dartantic embed search -q <query> <embeddings.json>');
      return ExitCodes.invalidArguments;
    }

    final settings = await loadSettings();
    final cwd = getEffectiveWorkingDirectory();

    var embeddingsPath =
        files.first.startsWith('/') ? files.first : '$cwd/${files.first}';

    // Remove trailing slash for directory check
    if (embeddingsPath.endsWith('/')) {
      embeddingsPath = embeddingsPath.substring(0, embeddingsPath.length - 1);
    }

    // Check if it's a directory
    final dir = Directory(embeddingsPath);
    final file = File(embeddingsPath);

    final embeddingsFiles = <File>[];
    if (await dir.exists()) {
      // Find all .json files in directory
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.json')) {
          embeddingsFiles.add(entity);
        }
      }
      if (embeddingsFiles.isEmpty) {
        stderr.writeln(
          'Error: No embeddings JSON files found in directory: ${files.first}',
        );
        return ExitCodes.invalidArguments;
      }
    } else if (await file.exists()) {
      embeddingsFiles.add(file);
    } else {
      stderr.writeln('Error: Embeddings file not found: ${files.first}');
      return ExitCodes.invalidArguments;
    }

    // Load and merge all embeddings files
    final allDocuments = <dynamic>[];
    String? modelFromFile;

    for (final embeddingsFile in embeddingsFiles) {
      final embeddingsJson = await embeddingsFile.readAsString();
      final Map<String, dynamic> embeddingsData;
      embeddingsData = jsonDecode(embeddingsJson) as Map<String, dynamic>;
      modelFromFile ??= embeddingsData['model'] as String?;
      final docs = embeddingsData['documents'] as List<dynamic>?;
      if (docs != null) {
        allDocuments.addAll(docs);
      }
    }

    // Determine agent name (use same model as embeddings file if possible)
    final agentName = agent ??
        modelFromFile ??
        Platform.environment['DARTANTIC_AGENT'] ??
        settings.defaultAgent ??
        'google';

    final agentSettings = settings.agents[agentName];
    final modelString = agentSettings?.model ?? agentName;

    // Create agent
    final agentInstance = Agent(modelString);

    // Embed the query
    final queryResult = await agentInstance.embedQuery(query);
    final queryEmbedding = queryResult.embeddings;

    // Calculate similarities for all chunks
    final results = <Map<String, dynamic>>[];
    final documents = allDocuments;

    for (final doc in documents) {
      final docMap = doc as Map<String, dynamic>;
      final filePath = docMap['file'] as String;
      final chunks = docMap['chunks'] as List<dynamic>;

      for (final chunk in chunks) {
        final chunkMap = chunk as Map<String, dynamic>;
        final vector = (chunkMap['vector'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList();
        final similarity =
            EmbeddingsModel.cosineSimilarity(queryEmbedding, vector);

        results.add({
          'file': filePath,
          'text': chunkMap['text'],
          'offset': chunkMap['offset'],
          'similarity': similarity,
        });
      }
    }

    // Sort by similarity (descending)
    results.sort(
      (a, b) =>
          (b['similarity'] as double).compareTo(a['similarity'] as double),
    );

    // Output results
    final output = {
      'query': query,
      'results': results.take(10).toList(), // Top 10 results
    };

    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));

    return ExitCodes.success;
  }
}
