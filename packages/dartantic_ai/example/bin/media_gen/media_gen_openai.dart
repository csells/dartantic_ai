import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:example/example.dart';

void main() async {
  const outputDir = 'tmp';

  stdout.writeln('=== OpenAI Responses Media Generation Demo ===');
  stdout.writeln('Assets will be written to: $outputDir\n');

  final agent = Agent('openai-responses');

  // Image generation
  stdout.writeln('## OpenAI: Image via generateMedia()');
  final imageResult = await agent.generateMedia(
    'Create a minimalist robot mascot for a developer conference. '
    'Use high contrast black and white line art.',
    mimeTypes: const ['image/png'],
  );
  dumpAssets(
    imageResult.assets,
    '$outputDir/bw',
    fallbackPrefix: 'openai_robot',
  );

  // Image editing with attachment (uses code execution)
  stdout.writeln('\n## OpenAI: Image Editing via generateMedia()');
  final robotAsset = imageResult.assets.firstOrNull;
  if (robotAsset is DataPart) {
    final editResult = await agent.generateMedia(
      'Colorize this black and white robot drawing. Make the robot body '
      'blue, the eyes bright green, and add orange/yellow accents. '
      'Preserve all the original black lines.',
      mimeTypes: const ['image/png'],
      attachments: [robotAsset],
    );
    dumpAssets(
      editResult.assets,
      '$outputDir/color',
      fallbackPrefix: 'openai_robot_colorized',
    );
  }

  // PDF generation
  stdout.writeln('\n## OpenAI: PDF via generateMedia()');
  final pdfResult = await agent.generateMedia(
    'Create a one-page PDF file called "status_report.pdf" with the title '
    '"Project Status" and three bullet points summarizing a software project.',
    mimeTypes: const ['application/pdf'],
  );
  dumpAssets(pdfResult.assets, outputDir, fallbackPrefix: 'openai_report');

  // CSV generation
  stdout.writeln('\n## OpenAI: CSV via generateMedia()');
  final csvResult = await agent.generateMedia(
    'Create a CSV file called "metrics.csv" with columns: date, users, '
    'revenue. Add 5 rows of sample data for the past week.',
    mimeTypes: const ['text/csv'],
  );
  dumpAssets(csvResult.assets, outputDir, fallbackPrefix: 'openai_data');
  exit(0);
}
