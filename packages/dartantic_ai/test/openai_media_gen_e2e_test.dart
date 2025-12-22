@Tags(['e2e'])
library;

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    stdout.writeln('${record.level.name}: ${record.time}: ${record.message}');
  });

  group('OpenAI Media Generation E2E', () {
    late OpenAIResponsesProvider provider;
    late MediaGenerationModel model;

    setUp(() {
      final apiKey = Platform.environment['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw StateError('OPENAI_API_KEY environment variable not set');
      }
      provider = OpenAIResponsesProvider(apiKey: apiKey);
      model = provider.createMediaModel();
    });

    test('generates an image', () async {
      final stream = model.generateMediaStream(
        'Create a minimalist robot mascot for a developer conference',
        mimeTypes: ['image/png'],
      );

      final results = await stream.toList();
      expect(results, isNotEmpty);

      final result = results.firstWhere(
        (r) => r.assets.isNotEmpty || r.links.isNotEmpty,
        orElse: () => fail('No image generated'),
      );

      expect(
        result.assets.isNotEmpty || result.links.isNotEmpty,
        isTrue,
        reason: 'Should return at least one asset or link',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test(
      'edits an image with attachment',
      () async {
        // Load test image
        const testImagePath = 'test/files/robot_bw.png';
        final imageBytes = await File(testImagePath).readAsBytes();
        final imagePart = DataPart(imageBytes, mimeType: 'image/png');

        final stream = model.generateMediaStream(
          'Colorize this black and white robot drawing. '
          'Make the robot body blue and the eyes green.',
          mimeTypes: ['image/png'],
          attachments: [imagePart],
        );

        final results = await stream.toList();
        expect(results, isNotEmpty);

        final result = results.firstWhere(
          (r) => r.assets.isNotEmpty,
          orElse: () => fail('No image generated'),
        );

        expect(result.assets, isNotEmpty);
        final asset = result.assets.first as DataPart;
        expect(asset.mimeType, contains('image/'));
        expect(asset.bytes, isNotEmpty);
        // Verify the output is different from input (was edited)
        expect(asset.bytes, isNot(equals(imageBytes)));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'generates media with multiple attachment types',
      () async {
        // Load test image
        const testImagePath = 'test/files/robot_bw.png';
        final imageBytes = await File(testImagePath).readAsBytes();
        final imagePart = DataPart(imageBytes, mimeType: 'image/png');

        // Add a text part as well
        const textPart = TextPart('Additional context for generation');

        final stream = model.generateMediaStream(
          'Create a colorful variation of this robot',
          mimeTypes: ['image/png'],
          attachments: [imagePart, textPart],
        );

        final results = await stream.toList();
        expect(results, isNotEmpty);

        final result = results.firstWhere(
          (r) => r.assets.isNotEmpty,
          orElse: () => fail('No image generated'),
        );

        expect(result.assets, isNotEmpty);
        final asset = result.assets.first as DataPart;
        expect(asset.mimeType, contains('image/'));
        expect(asset.bytes, isNotEmpty);
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
