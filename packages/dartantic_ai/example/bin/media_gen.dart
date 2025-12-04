import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

/// Demonstrates the `generateMedia()` API across all three providers:
/// - Google (Imagen 3 for images, code execution for PDFs/text)
/// - OpenAI Responses (DALL-E 3 for images, code interpreter for PDFs/text)
/// - Anthropic (code execution for all file types)
///
/// Each provider generates: image (PNG), document (PDF), and data file (CSV).
///
/// Uses specific prompts with explicit filenames for reliable file generation.
void main() async {
  final outputDir = Directory('tmp');
  if (!outputDir.existsSync()) outputDir.createSync(recursive: true);

  stdout.writeln('\n=== Media Generation API Demo ===');
  stdout.writeln('Using generateMedia() / generateMediaStream()');
  stdout.writeln('Assets will be written to: ${outputDir.path}\n');

  await generateWithGoogle(outputDir);
  await generateWithOpenAI(outputDir);
  await generateWithAnthropic(outputDir);

  stdout.writeln('\n✅ Media generation demo complete!');
  exit(0);
}

// ============================================================================
// Google: generateMedia() with Imagen 3 and code execution fallback
// ============================================================================
Future<void> generateWithGoogle(Directory dir) async {
  stdout.writeln('━━━ Google (generateMedia API) ━━━');
  final agent = Agent('google:gemini-2.5-flash-image');

  // Image generation (uses Imagen 3)
  stdout.writeln('\n## Google: Image via generateMedia()');
  final imageResult = await agent.generateMedia(
    'Create a minimalist robot mascot for a developer conference. '
    'Use high contrast black and white line art.',
    mimeTypes: const ['image/png'],
    options: const GoogleMediaGenerationModelOptions(
      responseModalities: ['IMAGE'],
    ),
  );
  _saveAssets(imageResult.assets, dir, 'google_image');

  // PDF generation (auto-fallback to code execution)
  stdout.writeln('\n## Google: PDF via generateMedia()');
  final pdfResult = await agent.generateMedia(
    'Create a one-page PDF file called "status_report.pdf" with the title '
    '"Project Status" and three bullet points summarizing a software project.',
    mimeTypes: const ['application/pdf'],
  );
  _saveAssets(pdfResult.assets, dir, 'google_report');

  // CSV generation (auto-fallback to code execution)
  stdout.writeln('\n## Google: CSV via generateMedia()');
  final csvResult = await agent.generateMedia(
    'Create a CSV file called "metrics.csv" with columns: date, users, '
    'revenue. Add 5 rows of sample data for the past week.',
    mimeTypes: const ['text/csv'],
  );
  _saveAssets(csvResult.assets, dir, 'google_data');
}

// ============================================================================
// OpenAI Responses: generateMedia() with DALL-E 3 and code interpreter
// ============================================================================
Future<void> generateWithOpenAI(Directory dir) async {
  stdout.writeln('\n━━━ OpenAI Responses (generateMedia API) ━━━');
  final agent = Agent('openai-responses');

  // Image generation (uses DALL-E 3)
  stdout.writeln('\n## OpenAI: Image via generateMedia()');
  final imageResult = await agent.generateMedia(
    'Create a minimalist robot mascot for a developer conference. '
    'Use high contrast black and white line art.',
    mimeTypes: const ['image/png'],
  );
  _saveAssets(imageResult.assets, dir, 'openai_image');

  // PDF generation (uses code interpreter)
  stdout.writeln('\n## OpenAI: PDF via generateMedia()');
  final pdfResult = await agent.generateMedia(
    'Create a one-page PDF file called "status_report.pdf" with the title '
    '"Project Status" and three bullet points summarizing a software project.',
    mimeTypes: const ['application/pdf'],
  );
  _saveAssets(pdfResult.assets, dir, 'openai_report');

  // CSV generation (uses code interpreter)
  stdout.writeln('\n## OpenAI: CSV via generateMedia()');
  final csvResult = await agent.generateMedia(
    'Create a CSV file called "metrics.csv" with columns: date, users, '
    'revenue. Add 5 rows of sample data for the past week.',
    mimeTypes: const ['text/csv'],
  );
  _saveAssets(csvResult.assets, dir, 'openai_data');
}

// ============================================================================
// Anthropic: generateMedia() with code execution for all file types
// ============================================================================
Future<void> generateWithAnthropic(Directory dir) async {
  stdout.writeln('\n━━━ Anthropic (generateMedia API) ━━━');
  final agent = Agent('anthropic');

  // Image generation (uses matplotlib via code execution)
  stdout.writeln('\n## Anthropic: Image via generateMedia()');
  final imageResult = await agent.generateMedia(
    'Create a simple logo image: a blue circle with the text "AI" '
    'in white in the center.',
    mimeTypes: const ['image/png'],
  );
  _saveAssets(imageResult.assets, dir, 'anthropic_logo');

  // PDF generation (uses reportlab via code execution)
  stdout.writeln('\n## Anthropic: PDF via generateMedia()');
  final pdfResult = await agent.generateMedia(
    'Create a one-page PDF file called "status_report.pdf" with the title '
    '"Project Status" and three bullet points summarizing a software project.',
    mimeTypes: const ['application/pdf'],
  );
  _saveAssets(pdfResult.assets, dir, 'anthropic_report');

  // CSV generation (uses file writes via code execution)
  stdout.writeln('\n## Anthropic: CSV via generateMedia()');
  final csvResult = await agent.generateMedia(
    'Create a CSV file called "metrics.csv" with columns: date, users, '
    'revenue. Add 5 rows of sample data for the past week.',
    mimeTypes: const ['text/csv'],
  );
  _saveAssets(csvResult.assets, dir, 'anthropic_data');
}

// ============================================================================
// Helper functions
// ============================================================================
void _saveAssets(List<Part> assets, Directory dir, String fallbackPrefix) {
  if (assets.isEmpty) {
    stdout.writeln('  ⚠️  No assets generated');
    return;
  }
  for (final part in assets) {
    if (part is! DataPart) continue;
    final name = _resolveName(part, fallbackPrefix);
    final file = File('${dir.path}/$name');
    file.writeAsBytesSync(part.bytes);
    stdout.writeln('  💾 Saved: ${file.path} (${part.mimeType})');
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
