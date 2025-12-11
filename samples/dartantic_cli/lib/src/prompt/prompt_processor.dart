import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dotprompt_dart/dotprompt_dart.dart';
import 'package:path/path.dart' as p;

/// Result of processing a prompt
class ProcessedPrompt {
  ProcessedPrompt({
    required this.prompt,
    required this.attachments,
    this.modelOverride,
  });

  final String prompt;
  final List<Part> attachments;
  final String? modelOverride;
}

/// Processes prompts, handling @file patterns and .prompt files
class PromptProcessor {
  PromptProcessor({String? workingDirectory})
      : _workingDirectory = workingDirectory ?? Directory.current.path;

  final String _workingDirectory;

  /// Process a prompt, extracting attachments and handling .prompt files
  Future<ProcessedPrompt> process(
    String rawPrompt, {
    List<String> templateVariables = const [],
  }) async {
    // Check if prompt starts with @file
    if (rawPrompt.startsWith('@')) {
      return _processFilePrompt(rawPrompt.substring(1), templateVariables);
    }

    // Process inline @file patterns
    return _processInlineAttachments(rawPrompt);
  }

  Future<ProcessedPrompt> _processFilePrompt(
    String filePath,
    List<String> templateVariables,
  ) async {
    final resolvedPath = _resolvePath(filePath);
    final content = await File(resolvedPath).readAsString();

    // Check if .prompt file (dotprompt)
    if (filePath.endsWith('.prompt')) {
      return _processDotPrompt(content, templateVariables);
    }

    // Regular file - use as prompt text
    return _processInlineAttachments(content);
  }

  Future<ProcessedPrompt> _processDotPrompt(
    String content,
    List<String> templateVariables,
  ) async {
    final dotPrompt = DotPrompt(content);

    // Parse template variables (key=value format)
    final variables = <String, Object>{};
    for (final variable in templateVariables) {
      final parts = variable.split('=');
      if (parts.length == 2) {
        variables[parts[0]] = parts[1];
      }
    }

    // Render the prompt with variables (empty map uses defaults from frontmatter)
    final renderedPrompt =
        variables.isEmpty ? dotPrompt.render() : dotPrompt.render(input: variables);

    // Get model override from frontmatter if present
    final modelOverride = dotPrompt.frontMatter.model;

    return ProcessedPrompt(
      prompt: renderedPrompt,
      attachments: [],
      modelOverride: modelOverride,
    );
  }

  Future<ProcessedPrompt> _processInlineAttachments(String prompt) async {
    final attachments = <Part>[];
    var processedPrompt = prompt;

    // Pattern: @filepath or @"filepath with spaces" or "@filepath"
    // Match @"path" or @path patterns
    final pattern = RegExp(r'@"([^"]+)"|"@([^"]+)"|@(\S+)');

    final matches = pattern.allMatches(prompt).toList();

    // Process matches in reverse order to preserve string indices
    for (final match in matches.reversed) {
      String filePath;
      if (match.group(1) != null) {
        // @"path with spaces"
        filePath = match.group(1)!;
      } else if (match.group(2) != null) {
        // "@path with spaces"
        filePath = match.group(2)!;
      } else {
        // @path
        filePath = match.group(3)!;
      }

      final resolvedPath = _resolvePath(filePath);
      final file = File(resolvedPath);

      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        // XFile with path will auto-detect MIME type via DataPart.fromFile
        final xFile = XFile.fromData(bytes, path: resolvedPath);
        attachments.add(await DataPart.fromFile(xFile));

        // Remove the @file pattern from the prompt
        processedPrompt = processedPrompt.replaceRange(
          match.start,
          match.end,
          '',
        );
      }
    }

    // Clean up extra whitespace
    processedPrompt = processedPrompt.replaceAll(RegExp(r'\s+'), ' ').trim();

    return ProcessedPrompt(
      prompt: processedPrompt,
      attachments: attachments.reversed.toList(), // Restore original order
    );
  }

  String _resolvePath(String filePath) {
    // Remove surrounding quotes if present
    var path = filePath;
    if (path.startsWith('"') && path.endsWith('"')) {
      path = path.substring(1, path.length - 1);
    }

    if (p.isAbsolute(path)) {
      return path;
    }
    return p.join(_workingDirectory, path);
  }
}
