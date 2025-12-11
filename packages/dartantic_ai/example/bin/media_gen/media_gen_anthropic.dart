import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main() async {
  const outputDir = 'tmp';

  stdout.writeln('=== Anthropic Media Generation Demo ===');
  stdout.writeln('Assets will be written to: $outputDir\n');

  final agent = Agent('anthropic');

  // Image generation (uses matplotlib via code execution)
  stdout.writeln('## Anthropic: Image via generateMedia()');
  final imageResult = await agent.generateMedia(
    'Create a simple logo image: a blue circle with the text "AI" '
    'in white in the center.',
    mimeTypes: const ['image/png'],
  );
  dumpAssets(imageResult.assets, outputDir, fallbackPrefix: 'anthropic_logo');

  // PDF generation (uses reportlab via code execution)
  stdout.writeln('\n## Anthropic: PDF via generateMedia()');
  final pdfResult = await agent.generateMedia(
    'Create a one-page PDF file called "status_report.pdf" with the title '
    '"Project Status" and three bullet points summarizing a software project.',
    mimeTypes: const ['application/pdf'],
  );
  dumpAssets(pdfResult.assets, outputDir, fallbackPrefix: 'anthropic_report');

  // CSV generation (uses file writes via code execution)
  stdout.writeln('\n## Anthropic: CSV via generateMedia()');
  final csvResult = await agent.generateMedia(
    'Create a CSV file called "metrics.csv" with columns: date, users, '
    'revenue. Add 5 rows of sample data for the past week.',
    mimeTypes: const ['text/csv'],
  );
  dumpAssets(csvResult.assets, outputDir, fallbackPrefix: 'anthropic_data');
  exit(0);
}
