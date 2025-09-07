// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dartantic_interface/dartantic_interface.dart';

void dumpMessages(List<ChatMessage> history) {
  print('--------------------------------');
  print('# Message History:');
  for (final message in history) {
    print('- ${_messageToSingleLine(message)}');
    if (message.metadata.isNotEmpty) {
      print('  Metadata: ${message.metadata}');
    }
  }
  print('--------------------------------');
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
  print('\n# $name');
  for (final tool in tools) {
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(jsonDecode(tool.inputSchema.toJson()));
    print('\n## Tool');
    print('- name: ${tool.name}');
    print('- description: ${tool.description}');
    print('- inputSchema: $json');
  }
}

/// Dumps a ChatResult with its metadata for debugging
void dumpChatResult(ChatResult result, {String? label}) {
  if (label != null) {
    print('\n=== $label ===');
  }

  print('Result ID: ${result.id}');

  // Show usage if available
  if (result.usage.totalTokens != null) {
    print(
      'Usage: ${result.usage.promptTokens ?? 0} prompt + '
      '${result.usage.responseTokens ?? 0} response = '
      '${result.usage.totalTokens} total tokens',
    );
  }

  // Show metadata if present
  if (result.metadata.isNotEmpty) {
    print('\nMetadata:');
    // Truncate metadata before encoding
    final truncated = truncateDeep(result.metadata) as Map<String, dynamic>;
    const encoder = JsonEncoder.withIndent('  ');
    print(encoder.convert(truncated));
  }

  // Show messages
  if (result.messages.isNotEmpty) {
    print('\nMessages:');
    for (var i = 0; i < result.messages.length; i++) {
      final msg = result.messages[i];
      print('  [$i] ${_messageToSummary(msg)}');
    }
  }

  // Show output if it's a ChatMessage
  if (result.output is ChatMessage) {
    final outputSummary = _messageToSummary(result.output as ChatMessage);
    print('\nOutput: $outputSummary');
  } else {
    print('\nOutput: ${result.output}');
  }
}

/// Dumps streaming results with metadata tracking
void dumpStreamingResults(List<ChatResult> results) {
  print('\n=== Streaming Results Summary ===');
  print('Total chunks: ${results.length}');

  // Collect all unique metadata keys
  final allMetadataKeys = <String>{};
  for (final result in results) {
    allMetadataKeys.addAll(result.metadata.keys);
  }

  if (allMetadataKeys.isNotEmpty) {
    print('\nMetadata keys found: ${allMetadataKeys.join(', ')}');

    // Show interesting metadata
    for (final result in results) {
      final meta = result.metadata;
      if (meta.containsKey('suppressed_text') ||
          meta.containsKey('suppressed_tool_calls') ||
          meta.containsKey('extra_return_results')) {
        print('\nChunk with suppressed content:');
        // Truncate metadata before encoding
        final truncated = truncateDeep(meta) as Map<String, dynamic>;
        print(const JsonEncoder.withIndent('  ').convert(truncated));
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

Future<void> dumpStream(Stream<ChatResult<String>> stream) async {
  await stream.forEach((r) => stdout.write(r.output));
  stdout.write('\n');
}

/// Truncates any value to a maximum length, handling different types
String truncateValue(dynamic value, {int maxLength = 512}) {
  final str = value.toString();
  if (str.length <= maxLength) return str;
  return '${str.substring(0, maxLength)}...';
}

/// Recursively truncates values in a map/list structure
dynamic truncateDeep(dynamic obj, {int maxLength = 512}) {
  if (obj is Map) {
    // Create a new Map<String, dynamic> to ensure proper type
    final result = <String, dynamic>{};
    obj.forEach((key, value) {
      result[key.toString()] = truncateDeep(value, maxLength: maxLength);
    });
    return result;
  } else if (obj is List) {
    return obj
        .map((item) => truncateDeep(item, maxLength: maxLength))
        .toList();
  } else if (obj is String) {
    return obj.length > maxLength ? '${obj.substring(0, maxLength)}...' : obj;
  } else {
    // For other types, convert to string and truncate if needed
    final str = obj.toString();
    return str.length > maxLength ? '${str.substring(0, maxLength)}...' : obj;
  }
}

/// Dumps metadata in a formatted way with all values truncated
void dumpMetadata(
  Map<String, dynamic> metadata, {
  String prefix = '',
  int maxLength = 512,
}) {
  if (metadata.isEmpty) return;

  final truncated =
      truncateDeep(metadata, maxLength: maxLength) as Map<String, dynamic>;

  for (final entry in truncated.entries) {
    final key = entry.key;
    final value = entry.value;

    // Special handling for structured metadata (like web_search with stage/data)
    if (value is Map<String, dynamic> && value.containsKey('stage')) {
      stdout
          .writeln('$prefix[$key/${value['stage']}] ${value['data'] ?? ''}');
    } else {
      stdout.writeln('$prefix[$key] $value');
    }
  }
}
