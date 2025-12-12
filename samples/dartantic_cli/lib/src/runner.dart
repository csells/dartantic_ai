import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:json_schema/json_schema.dart';
import 'package:yaml/yaml.dart';

import 'embeddings/chunker.dart';
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
    )
    // Generate command options
    ..addMultiOption(
      'mime',
      help: 'MIME type to generate (required for generate command, repeatable)',
    )
    // Embed command options
    ..addOption(
      'query',
      abbr: 'q',
      help: 'Search query for embed search',
    )
    ..addOption(
      'chunk-size',
      help: 'Chunk size in characters (default: 512)',
    )
    ..addOption(
      'chunk-overlap',
      help: 'Chunk overlap in characters (default: 100)',
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
          return _runGenerate(results, settings);
        case 'embed':
          return _runEmbed(results, settings);
        case 'models':
          return _runModels(results, settings);
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

  Future<int> _runGenerate(ArgResults results, Settings settings) async {
    // Parse --mime (required for generate command)
    final mimeTypes = results['mime'] as List<String>;
    if (mimeTypes.isEmpty) {
      stderr.writeln('Error: --mime is required for generate command');
      return ExitCodes.invalidArguments;
    }

    // Determine agent name: CLI arg > env var > settings default > 'google'
    final agentName = results['agent'] as String? ??
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

    // Process prompt (handle @files, etc.)
    final promptProcessor = PromptProcessor(workingDirectory: workingDirectory);
    final processed = await promptProcessor.process(rawPrompt);

    // Resolve agent: look up in settings, otherwise pass directly to Agent
    final agentSettings = settings.agents[agentName];
    final modelString = agentSettings?.model ?? agentName;

    // Create agent
    final agent = Agent(modelString);

    // Get output directory
    final outputDir = results['output-dir'] as String? ?? '.';

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
        final filename = asset.name ?? _generateFilename(asset.mimeType);
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

  Future<int> _runEmbed(ArgResults results, Settings settings) async {
    // Check for subcommand: embed create or embed search
    final rest = results.rest;

    // Find the subcommand after 'embed'
    final embedIndex = rest.indexOf('embed');
    final subcommandArgs =
        embedIndex >= 0 ? rest.sublist(embedIndex + 1) : rest.sublist(1);

    if (subcommandArgs.isEmpty) {
      stderr.writeln('Error: embed command requires a subcommand (create or search)');
      stderr.writeln('Usage: dartantic embed create <files...>');
      stderr.writeln('       dartantic embed search -q <query> <embeddings.json>');
      return ExitCodes.invalidArguments;
    }

    final subcommand = subcommandArgs.first;
    final files = subcommandArgs.skip(1).toList();

    switch (subcommand) {
      case 'create':
        return _runEmbedCreate(results, settings, files);
      case 'search':
        return _runEmbedSearch(results, settings, files);
      default:
        stderr.writeln('Error: Unknown embed subcommand "$subcommand"');
        stderr.writeln('Valid subcommands: create, search');
        return ExitCodes.invalidArguments;
    }
  }

  Future<int> _runEmbedCreate(
    ArgResults results,
    Settings settings,
    List<String> files,
  ) async {
    if (files.isEmpty) {
      stderr.writeln('Error: No files provided for embed create');
      stderr.writeln('Usage: dartantic embed create <files...>');
      return ExitCodes.invalidArguments;
    }

    // Determine agent name
    final agentName = results['agent'] as String? ??
        Platform.environment['DARTANTIC_AGENT'] ??
        settings.defaultAgent ??
        'google';

    // Resolve agent
    final agentSettings = settings.agents[agentName];
    final modelString = agentSettings?.model ?? agentName;

    // Parse chunk options
    final chunkSizeStr = results['chunk-size'] as String?;
    final chunkOverlapStr = results['chunk-overlap'] as String?;

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
    final workingDirectory = results['cwd'] as String?;
    final cwd = workingDirectory ?? Directory.current.path;

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

  Future<int> _runEmbedSearch(
    ArgResults results,
    Settings settings,
    List<String> files,
  ) async {
    // Require -q query
    final query = results['query'] as String?;
    if (query == null || query.isEmpty) {
      stderr.writeln('Error: -q/--query is required for embed search');
      stderr.writeln('Usage: dartantic embed search -q <query> <embeddings.json>');
      return ExitCodes.invalidArguments;
    }

    if (files.isEmpty) {
      stderr.writeln('Error: No embeddings file provided');
      stderr.writeln('Usage: dartantic embed search -q <query> <embeddings.json>');
      return ExitCodes.invalidArguments;
    }

    // Load embeddings file
    final workingDirectory = results['cwd'] as String?;
    final cwd = workingDirectory ?? Directory.current.path;
    final embeddingsPath =
        files.first.startsWith('/') ? files.first : '$cwd/${files.first}';
    final embeddingsFile = File(embeddingsPath);

    if (!await embeddingsFile.exists()) {
      stderr.writeln('Error: Embeddings file not found: ${files.first}');
      return ExitCodes.invalidArguments;
    }

    final embeddingsJson = await embeddingsFile.readAsString();
    final Map<String, dynamic> embeddingsData;
    try {
      embeddingsData = jsonDecode(embeddingsJson) as Map<String, dynamic>;
    } on FormatException catch (e) {
      stderr.writeln('Error: Invalid embeddings JSON: ${e.message}');
      return ExitCodes.invalidArguments;
    }

    // Determine agent name (use same model as embeddings file if possible)
    final agentName = results['agent'] as String? ??
        embeddingsData['model'] as String? ??
        Platform.environment['DARTANTIC_AGENT'] ??
        settings.defaultAgent ??
        'google';

    final agentSettings = settings.agents[agentName];
    final modelString = agentSettings?.model ?? agentName;

    // Create agent
    final agent = Agent(modelString);

    // Embed the query
    final queryResult = await agent.embedQuery(query);
    final queryEmbedding = queryResult.embeddings;

    // Calculate similarities for all chunks
    final results2 = <Map<String, dynamic>>[];
    final documents = embeddingsData['documents'] as List<dynamic>;

    for (final doc in documents) {
      final docMap = doc as Map<String, dynamic>;
      final file = docMap['file'] as String;
      final chunks = docMap['chunks'] as List<dynamic>;

      for (final chunk in chunks) {
        final chunkMap = chunk as Map<String, dynamic>;
        final vector = (chunkMap['vector'] as List<dynamic>)
            .map((e) => (e as num).toDouble())
            .toList();
        final similarity =
            EmbeddingsModel.cosineSimilarity(queryEmbedding, vector);

        results2.add({
          'file': file,
          'text': chunkMap['text'],
          'offset': chunkMap['offset'],
          'similarity': similarity,
        });
      }
    }

    // Sort by similarity (descending)
    results2.sort(
      (a, b) =>
          (b['similarity'] as double).compareTo(a['similarity'] as double),
    );

    // Output results
    final output = {
      'query': query,
      'results': results2.take(10).toList(), // Top 10 results
    };

    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));

    return ExitCodes.success;
  }

  Future<int> _runModels(ArgResults results, Settings settings) async {
    // Determine provider: CLI -a arg > env var > settings default > 'google'
    final agentName = results['agent'] as String? ??
        Platform.environment['DARTANTIC_AGENT'] ??
        settings.defaultAgent ??
        'google';

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

  /// Generate a filename based on MIME type
  String _generateFilename(String mimeType) {
    final ext = switch (mimeType) {
      'image/png' => 'png',
      'image/jpeg' || 'image/jpg' => 'jpg',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'application/pdf' => 'pdf',
      'text/csv' => 'csv',
      'text/plain' => 'txt',
      'application/json' => 'json',
      _ => 'bin',
    };
    return 'generated_${DateTime.now().millisecondsSinceEpoch}.$ext';
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
