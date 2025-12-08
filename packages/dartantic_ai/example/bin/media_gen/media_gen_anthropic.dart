import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

/// Demonstrates Anthropic media generation via `generateMedia()`.
///
/// Anthropic uses code execution (Code Interpreter / Analysis tool) for all
/// file types including images (via matplotlib), PDFs (via reportlab), and
/// text/CSV files.
void main() async {
  final outputDir = Directory('tmp');
  if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

  stdout.writeln('\n=== Anthropic Media Generation Demo ===');
  stdout.writeln('Assets will be written to: ${outputDir.path}\n');

  final agent = Agent('anthropic');

  // Image generation (uses matplotlib via code execution)
  stdout.writeln('## Anthropic: Image via generateMedia()');
  final imageResult = await agent.generateMedia(
    'Create a simple logo image: a blue circle with the text "AI" '
    'in white in the center.',
    mimeTypes: const ['image/png'],
  );
  _saveAssets(imageResult.assets, outputDir, 'anthropic_logo');

  // PDF generation (uses reportlab via code execution)
  stdout.writeln('\n## Anthropic: PDF via generateMedia()');
  final pdfResult = await agent.generateMedia(
    'Create a one-page PDF file called "status_report.pdf" with the title '
    '"Project Status" and three bullet points summarizing a software project.',
    mimeTypes: const ['application/pdf'],
  );
  _saveAssets(pdfResult.assets, outputDir, 'anthropic_report');

  // CSV generation (uses file writes via code execution)
  stdout.writeln('\n## Anthropic: CSV via generateMedia()');
  final csvResult = await agent.generateMedia(
    'Create a CSV file called "metrics.csv" with columns: date, users, '
    'revenue. Add 5 rows of sample data for the past week.',
    mimeTypes: const ['text/csv'],
  );
  _saveAssets(csvResult.assets, outputDir, 'anthropic_data');

  stdout.writeln('\nAnthropic media generation complete!');
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
