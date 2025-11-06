// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_ai/src/media_gen_models/anthropic/anthropic_files_client.dart';
import 'package:dartantic_ai/src/media_gen_models/anthropic/anthropic_tool_deliverable_tracker.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

void main(List<String> args) async {
  stdout.writeln('🧪 Anthropic Code Execution Tool Demo');

  final apiKey =
      Platform.environment['ANTHROPIC_API_KEY'] ??
      Platform.environment['ANTHROPIC_API_TEST_KEY']!;

  final filesClient = AnthropicFilesClient(
    apiKey: apiKey,
    betaFeatures: AnthropicServerSideTool.codeInterpreter.betaFeatures,
  );
  final tracker = AnthropicToolDeliverableTracker(
    filesClient,
    targetMimeTypes: const {'*/*'},
  );

  final agent = Agent(
    'anthropic',
    chatModelOptions: const AnthropicChatOptions(
      serverSideTools: {AnthropicServerSideTool.codeInterpreter},
    ),
  );

  const prompt = '''
Create a markdown file named analytics_report.md that explains how to run a
Dart CLI app, including setup steps and troubleshooting guidance.
''';

  final savedAssetKeys = <String>{};
  final seenLinks = <String>{};
  final history = <ChatMessage>[];

  try {
    stdout.writeln('User: $prompt');
    stdout.writeln('Claude:');

    await for (final chunk in agent.sendStream(prompt)) {
      stdout.write(chunk.output);
      history.addAll(chunk.messages);
      await _saveDeliverablesFromMetadata(
        tracker,
        chunk.metadata,
        savedAssetKeys,
        seenLinks,
      );
      dumpMetadata(chunk.metadata, prefix: '\n');
    }

    await _finishDeliverableCollection(tracker, savedAssetKeys);
  } finally {
    filesClient.close();
  }

  final conversation = history;

  _saveMessageDataParts(conversation, savedAssetKeys);
  if (savedAssetKeys.isEmpty) {
    stdout.writeln(
      '⚠️  No downloadable files were detected. Ensure Claude '
      r'copies files into $OUTPUT_DIR before finishing.',
    );
  }
  dumpMessages(conversation);

  stdout.writeln('✅ Completed code execution demo.');
}

const _outputDirectory = 'tmp';
int _downloadedFileCounter = 0;

Future<void> _saveDeliverablesFromMetadata(
  AnthropicToolDeliverableTracker tracker,
  Map<String, dynamic> metadata,
  Set<String> savedAssetKeys,
  Set<String> seenLinkUrls,
) async {
  if (metadata.isEmpty) return;

  final emission = await tracker.handleMetadata(metadata);
  if (emission.assets.isNotEmpty) {
    _saveDataParts(emission.assets, savedAssetKeys);
  }
  for (final link in emission.links) {
    final url = link.url.toString();
    if (seenLinkUrls.add(url)) {
      stdout.writeln('🔗 Tool link: $url');
    }
  }
}

Future<void> _finishDeliverableCollection(
  AnthropicToolDeliverableTracker tracker,
  Set<String> savedAssetKeys,
) async {
  final pending = await tracker.collectRecentFiles();
  if (pending.isEmpty) return;

  stdout.writeln(
    '📥 Retrieved ${pending.length} file(s) from the Anthropic Files API.',
  );
  _saveDataParts(pending, savedAssetKeys);
}

void _saveMessageDataParts(
  List<ChatMessage> messages,
  Set<String> savedAssetKeys,
) {
  final parts = messages.expand((message) => message.parts);
  _saveDataParts(parts, savedAssetKeys);
}

void _saveDataParts(Iterable<Part> parts, Set<String> savedAssetKeys) {
  for (final part in parts) {
    if (part is! DataPart) continue;

    final fileName = _resolveFileName(part);
    final key = '$fileName:${part.bytes.length}:${part.mimeType}';
    if (!savedAssetKeys.add(key)) continue;

    final file = File('$_outputDirectory/$fileName');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(part.bytes);
    stdout.writeln(
      '💾 Saved file: ${file.path} '
      '(${part.mimeType}, ${part.bytes.length} bytes)',
    );
  }
}

String _resolveFileName(DataPart part) {
  final candidate = part.name?.trim();
  if (candidate != null && candidate.isNotEmpty) {
    final sanitized = _sanitizeFileName(candidate);
    if (sanitized.isNotEmpty) return sanitized;
  }

  final extension = Part.extensionFromMimeType(part.mimeType);
  final index = ++_downloadedFileCounter;
  final generated = extension == null
      ? 'anthropic_file_$index'
      : 'anthropic_file_$index.$extension';
  return _sanitizeFileName(generated);
}

String _sanitizeFileName(String value) {
  final sanitized = value.replaceAll(RegExp(r'[\\/:<>\"|?*\r\n]+'), '_').trim();
  if (sanitized.isNotEmpty) return sanitized;
  return 'anthropic_file_${++_downloadedFileCounter}';
}
