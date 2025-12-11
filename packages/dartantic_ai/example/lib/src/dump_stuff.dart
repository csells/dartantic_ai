import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartantic_interface/dartantic_interface.dart';

void dumpMessages(List<ChatMessage> history) {
  stdout.writeln('--------------------------------');
  stdout.writeln('# Message History:');
  for (final message in history) {
    stdout.writeln('- ${_messageToSingleLine(message)}');
    if (message.metadata.isNotEmpty) {
      stdout.write('  Metadata: ');
      dumpMetadata(message.metadata);
    }
  }
  stdout.writeln('--------------------------------');
}

String _messageToSingleLine(ChatMessage message) {
  final roleName = message.role.name;
  final parts = [
    for (final part in message.parts)
      switch (part) {
        (final TextPart _) => 'TextPart{${part.text.trim()}}',
        (final DataPart _) =>
          'DataPart{mimeType: ${part.mimeType}, size: ${part.bytes.length}}',
        (final LinkPart _) => 'LinkPart{url: ${part.url}}',
        (final ToolPart _) => switch (part.kind) {
          ToolPartKind.call =>
            'ToolPart.call{id: ${part.id}, name: ${part.name}, '
                'args: ${part.arguments}}',
          ToolPartKind.result =>
            'ToolPart.result{id: ${part.id}, name: ${part.name}, '
                'result: ${part.result}}',
        },
        (final Part _) => throw UnimplementedError(),
      },
  ];

  return 'Message.$roleName(${parts.join(', ')})';
}

void dumpTools(String name, Iterable<Tool> tools) {
  stdout.writeln('\n# $name');
  for (final tool in tools) {
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonDecode(tool.inputSchema.toJson()));
    stdout.writeln('\n## Tool');
    stdout.writeln('- name: ${tool.name}');
    stdout.writeln('- description: ${tool.description}');
    stdout.writeln('- inputSchema: $json');
  }
}

/// Dumps a ChatResult with its metadata for debugging
void dumpChatResult(ChatResult result, {String? label}) {
  if (label != null) {
    stdout.writeln('\n=== $label ===');
  }

  stdout.writeln('Result ID: ${result.id}');

  // Show usage if available
  if (result.usage?.totalTokens != null) {
    final usage = result.usage!;
    stdout.writeln(
      'Usage: ${usage.promptTokens ?? 0} prompt + '
      '${usage.responseTokens ?? 0} response = '
      '${usage.totalTokens} total tokens',
    );
  }

  // Show metadata if present
  if (result.metadata.isNotEmpty) {
    stdout.writeln('\nMetadata:');
    const encoder = JsonEncoder.withIndent('  ');
    stdout.writeln(encoder.convert(result.metadata));
  }

  // Show messages
  if (result.messages.isNotEmpty) {
    stdout.writeln('\nMessages:');
    for (var i = 0; i < result.messages.length; i++) {
      final msg = result.messages[i];
      stdout.writeln('  [$i] ${_messageToSummary(msg)}');
    }
  }

  // Show output if it's a ChatMessage
  if (result.output is ChatMessage) {
    final outputSummary = _messageToSummary(result.output as ChatMessage);
    stdout.writeln('\nOutput: $outputSummary');
  } else {
    stdout.writeln('\nOutput: ${result.output}');
  }
}

/// Dumps streaming results with metadata tracking
void dumpStreamingResults(List<ChatResult> results) {
  stdout.writeln('\n=== Streaming Results Summary ===');
  stdout.writeln('Total chunks: ${results.length}');

  // Collect all unique metadata keys
  final allMetadataKeys = <String>{};
  for (final result in results) {
    allMetadataKeys.addAll(result.metadata.keys);
  }

  if (allMetadataKeys.isNotEmpty) {
    stdout.writeln('\nMetadata keys found: ${allMetadataKeys.join(', ')}');

    // Show interesting metadata
    for (final result in results) {
      final meta = result.metadata;
      if (meta.containsKey('suppressed_text') ||
          meta.containsKey('suppressed_tool_calls') ||
          meta.containsKey('extra_return_results')) {
        stdout.writeln('\nChunk with suppressed content:');
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(meta));
      }
    }
  }
}

String _messageToSummary(ChatMessage message) {
  final parts = <String>[];

  for (final part in message.parts) {
    if (part is TextPart) {
      final preview = part.text.length > 50
          ? '${part.text.substring(0, 47)}...'
          : part.text;
      parts.add('Text("$preview")');
    } else if (part is ToolPart) {
      if (part.kind == ToolPartKind.call) {
        parts.add('ToolCall(${part.name})');
      } else {
        parts.add('ToolResult(${part.name})');
      }
    } else if (part is DataPart) {
      parts.add('Data(${part.mimeType})');
    } else if (part is LinkPart) {
      parts.add('Link(${part.url})');
    }
  }

  return '${message.role.name}: [${parts.join(', ')}]';
}

void dumpUsage(LanguageModelUsage? usage) {
  if (usage == null) return;
  stdout.writeln('\n### Usage:');
  stdout.writeln('- Prompt tokens: ${usage.promptTokens}');
  stdout.writeln('- Response tokens: ${usage.responseTokens}');
  stdout.writeln('- Total tokens: ${usage.totalTokens}');
}

void dumpMetadata(
  Map<String, Object?> metadata, {
  String prefix = '',
  int maxLength = 64,
}) {
  if (metadata.isEmpty) return;
  final trimmed = _recursiveTrimJson(metadata, maxLength: maxLength);
  const encoder = JsonEncoder();
  final serialized = encoder.convert(trimmed);
  stdout.writeln('$prefix$serialized');
}

/// Recursively processes a JSON structure, trimming string values and
/// parsing string values that contain JSON
Object? _recursiveTrimJson(Object? value, {required int maxLength}) {
  if (value == null) return null;

  // Handle strings: try to parse as JSON, otherwise trim
  if (value is String) {
    // Try to parse as JSON
    try {
      final parsed = jsonDecode(value);
      // Recursively process the parsed JSON
      return _recursiveTrimJson(parsed, maxLength: maxLength);
      // ignore: avoid_catches_without_on_clauses
    } catch (_) {
      // Not JSON, just trim the string
      return _clip(value, maxLength: maxLength);
    }
  }

  // Handle lists recursively
  if (value is List) {
    return value
        .map((item) => _recursiveTrimJson(item, maxLength: maxLength))
        .toList();
  }

  // Handle maps recursively
  if (value is Map) {
    return value.map(
      (key, val) =>
          MapEntry(key, _recursiveTrimJson(val, maxLength: maxLength)),
    );
  }

  // All other primitives (numbers, bools, etc.) pass through unchanged
  return value;
}

String _clip(String input, {required int maxLength}) {
  if (input.length <= maxLength) return input;
  final safeLength = maxLength <= 3 ? maxLength : maxLength - 3;
  final prefix = safeLength <= 0 ? '' : input.substring(0, safeLength);
  return '$prefix...';
}

String clipWithNull(Object? value, {int maxLength = 256}) =>
    _clip(value?.toString() ?? 'null', maxLength: maxLength);

void dumpImage(String name, String baseFilename, Uint8List bytes) {
  final filename =
      'tmp/${baseFilename}_${DateTime.now().millisecondsSinceEpoch}.png';
  final out = File(filename);
  out.createSync(recursive: true);
  out.writeAsBytesSync(bytes);
  stdout.writeln('  🎨 $name mage saved: $filename (${bytes.length} bytes)');
}

/// Counter used by [resolveAssetName] for generating unique fallback names.
int _assetCounter = 0;

/// Saves DataParts to disk with deduplication and filename resolution.
///
/// - [parts] - List of Parts (only DataParts are saved)
/// - [outputDirectory] - Directory path to save files to
/// - [fallbackPrefix] - Prefix for generated filenames when name is missing
/// - [savedKeys] - Optional set for deduplication (prevents duplicate saves)
void dumpAssets(
  Iterable<Part> parts,
  String outputDirectory, {
  String fallbackPrefix = 'asset',
  Set<String>? savedKeys,
}) {
  final dir = Directory(outputDirectory);
  if (!dir.existsSync()) dir.createSync(recursive: true);

  var count = 0;
  for (final part in parts) {
    if (part is! DataPart) continue;
    final name = resolveAssetName(part, fallbackPrefix);

    // Skip duplicates if tracking
    if (savedKeys != null && !savedKeys.add(name)) continue;

    final file = File('$outputDirectory/$name');
    file.writeAsBytesSync(part.bytes);
    stdout.writeln(
      '  Saved: ${file.path} (${part.mimeType}, ${part.bytes.length} bytes)',
    );
    count++;
  }

  if (count == 0) {
    stdout.writeln('  No assets generated');
  }
}

/// Resolves a filename for a DataPart, sanitizing and adding extensions.
///
/// If the part has a name, sanitizes it. Otherwise generates a unique name
/// using [fallbackPrefix] and an auto-incrementing counter.
String resolveAssetName(DataPart part, String fallbackPrefix) {
  final existing = part.name?.trim();
  if (existing != null && existing.isNotEmpty) {
    // Sanitize the existing name
    return existing.replaceAll(RegExp(r'[\\/:]'), '_');
  }
  // Generate a unique fallback name
  final extension = Part.extensionFromMimeType(part.mimeType);
  final id = _assetCounter++;
  return extension == null
      ? '$fallbackPrefix-$id'
      : '$fallbackPrefix-$id.$extension';
}

/// Extracts DataParts from message history and saves them to disk.
///
/// This is a convenience function for code execution examples where
/// generated files appear as DataParts in the message history.
void dumpAssetsFromHistory(
  List<ChatMessage> history,
  String outputDirectory, {
  String fallbackPrefix = 'file',
}) {
  final allParts = history.expand((msg) => msg.parts);
  dumpAssets(allParts, outputDirectory, fallbackPrefix: fallbackPrefix);
}
