import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:example/example.dart';

void main() async {
  const model = 'anthropic';
  final outputDir = Directory('tmp');
  if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

  stdout.writeln(
    '\n=== Media generation using provider "$model" ===\n'
    'Assets will be written to: ${outputDir.path}',
  );

  await generateLogoImage(model, outputDir);
  await generatePdfBrief(model, outputDir);

  exit(0);
}

Future<void> generateLogoImage(String model, Directory dir) async {
  stdout.writeln('\n## Streaming image concept');

  const prompt =
      'Create a minimalist robot mascot for a developer conference. '
      'Use high contrast black and white line art.';

  var chunkIndex = 0;
  final agent = Agent(model);
  await for (final chunk in agent.generateMediaStream(
    prompt,
    mimeTypes: const ['image/png'],
  )) {
    chunkIndex++;
    stdout.writeln(
      '- Chunk $chunkIndex (complete: ${chunk.isComplete}) '
      'assets=${chunk.assets.length} links=${chunk.links.length}',
    );
    if (chunk.metadata.isNotEmpty) {
      dumpMetadata(chunk.metadata, prefix: '  ');
    }
    await _saveAssets(chunk.assets, dir, 'logo_chunk_$chunkIndex');
    _printLinks(chunk.links);
  }
}

Future<void> generatePdfBrief(String model, Directory dir) async {
  stdout.writeln('\n## Generating PDF project brief');

  const prompt =
      'Using your available tools, produce a concise PDF named '
      '"roadmap.pdf" that outlines three milestones for building a '
      'Flutter weather application. Keep it to a single page.';

  final agent = Agent(model);
  final result = await agent.generateMedia(
    prompt,
    mimeTypes: const ['application/pdf'],
  );

  stdout.writeln(
    '- Received ${result.assets.length} asset(s) and '
    '${result.links.length} link(s)',
  );
  if (result.metadata.isNotEmpty) {
    dumpMetadata(result.metadata, prefix: '  ');
  }
  await _saveAssets(result.assets, dir, 'roadmap');
  _printLinks(result.links);
  if (result.messages.isNotEmpty) {
    dumpMessages(result.messages);
  }
}

Future<void> _saveAssets(
  List<Part> assets,
  Directory dir,
  String fallbackPrefix,
) async {
  for (final part in assets) {
    if (part is! DataPart) continue;
    final sanitizedName = _resolveName(part, fallbackPrefix);
    final file = File('${dir.path}/$sanitizedName');
    await file.writeAsBytes(part.bytes);
    stdout.writeln('  Saved asset -> ${file.path} (${part.mimeType})');
  }
}

void _printLinks(List<LinkPart> links) {
  for (final link in links) {
    stdout.writeln(
      '  Link -> ${link.url} (${link.mimeType ?? 'unknown mime'})',
    );
  }
}

String _resolveName(DataPart part, String fallbackPrefix) {
  final existing = part.name?.trim();
  if (existing != null && existing.isNotEmpty) {
    return _sanitizeFileName(existing);
  }
  final extension = Part.extensionFromMimeType(part.mimeType);
  return extension == null
      ? '$fallbackPrefix-${_nextId()}'
      : '$fallbackPrefix-${_nextId()}.$extension';
}

String _sanitizeFileName(String name) =>
    name.replaceAll(RegExp(r'[\\/:]'), '_');

int _nextId() => _assetCounter++;

int _assetCounter = 0;
