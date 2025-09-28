import 'dart:convert';
import 'dart:io';

import 'package:dartantic_interface/dartantic_interface.dart';

void dumpMessages(List<ChatMessage> history) {
  stdout.writeln('--------------------------------');
  stdout.writeln('# Message History:');
  for (final message in history) {
    stdout.writeln('- ${_messageToSingleLine(message)}');
    if (message.metadata.isNotEmpty) {
      stdout.writeln('  Metadata: ${message.metadata}');
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
  if (result.usage.totalTokens != null) {
    stdout.writeln(
      'Usage: ${result.usage.promptTokens ?? 0} prompt + '
      '${result.usage.responseTokens ?? 0} response = '
      '${result.usage.totalTokens} total tokens',
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

void dumpUsage(LanguageModelUsage usage) {
  stdout.writeln('\n### Usage:');
  stdout.writeln('- Prompt tokens: ${usage.promptTokens}');
  stdout.writeln('- Response tokens: ${usage.responseTokens}');
  stdout.writeln('- Total tokens: ${usage.totalTokens}');
}
