import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

/// Demonstrates Google media generation via `generateMedia()`.
///
/// Google uses Imagen 3 for native image generation. Non-image formats
/// (PDF, CSV, text files) are NOT supported because Google's code execution
/// can only output Matplotlib graphs as images.
/// See: https://ai.google.dev/gemini-api/docs/code-execution
void main() async {
  final outputDir = Directory('tmp');
  if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

  stdout.writeln('\n=== Google Media Generation Demo ===');
  stdout.writeln('Assets will be written to: ${outputDir.path}\n');

  final agent = Agent('google:gemini-2.5-flash-image');

  // Image generation (uses Imagen 3)
  stdout.writeln('## Google: Image via generateMedia()');
  final imageResult = await agent.generateMedia(
    'Create a minimalist robot mascot for a developer conference. '
    'Use high contrast black and white line art.',
    mimeTypes: const ['image/png'],
    options: const GoogleMediaGenerationModelOptions(
      responseModalities: ['IMAGE'],
    ),
  );
  _saveAssets(imageResult.assets, outputDir, 'google_image');

  stdout.writeln('\nGoogle media generation complete!');
  exit(0);
}

void _saveAssets(List<Part> assets, Directory dir, String fallbackPrefix) {
  if (assets.isEmpty) {
    stdout.writeln('  No assets generated');
    return;
  }
  for (final part in assets) {
    if (part is! DataPart) continue;
    final name = _resolveName(part, fallbackPrefix);
    final file = File('${dir.path}/$name');
    file.writeAsBytesSync(part.bytes);
    stdout.writeln('  Saved: ${file.path} (${part.mimeType})');
  }
}

String _resolveName(DataPart part, String fallbackPrefix) {
  final existing = part.name?.trim();
  if (existing != null && existing.isNotEmpty) {
    return existing.replaceAll(RegExp(r'[\\/:]'), '_');
  }
  final extension = Part.extensionFromMimeType(part.mimeType);
  return extension == null
      ? '$fallbackPrefix-${_nextId()}'
      : '$fallbackPrefix-${_nextId()}.$extension';
}

int _nextId() => _assetCounter++;
int _assetCounter = 0;
