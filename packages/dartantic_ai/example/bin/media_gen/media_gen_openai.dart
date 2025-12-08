import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

/// Demonstrates OpenAI Responses media generation via `generateMedia()`.
///
/// OpenAI uses DALL-E 3 for image generation and code interpreter for
/// other file types (PDF, CSV, text files).
void main() async {
  final outputDir = Directory('tmp');
  if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

  stdout.writeln('\n=== OpenAI Responses Media Generation Demo ===');
  stdout.writeln('Assets will be written to: ${outputDir.path}\n');

  final agent = Agent('openai-responses');

  // Image generation (uses DALL-E 3)
  stdout.writeln('## OpenAI: Image via generateMedia()');
  final imageResult = await agent.generateMedia(
    'Create a minimalist robot mascot for a developer conference. '
    'Use high contrast black and white line art.',
    mimeTypes: const ['image/png'],
  );
  _saveAssets(imageResult.assets, outputDir, 'openai_image');

  // PDF generation (uses code interpreter)
  stdout.writeln('\n## OpenAI: PDF via generateMedia()');
  final pdfResult = await agent.generateMedia(
    'Create a one-page PDF file called "status_report.pdf" with the title '
    '"Project Status" and three bullet points summarizing a software project.',
    mimeTypes: const ['application/pdf'],
  );
  _saveAssets(pdfResult.assets, outputDir, 'openai_report');

  // CSV generation (uses code interpreter)
  stdout.writeln('\n## OpenAI: CSV via generateMedia()');
  final csvResult = await agent.generateMedia(
    'Create a CSV file called "metrics.csv" with columns: date, users, '
    'revenue. Add 5 rows of sample data for the past week.',
    mimeTypes: const ['text/csv'],
  );
  _saveAssets(csvResult.assets, outputDir, 'openai_data');

  stdout.writeln('\nOpenAI media generation complete!');
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
