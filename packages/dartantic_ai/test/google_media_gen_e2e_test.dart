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

  group('Google Media Generation E2E', () {
    late GoogleProvider provider;
    late MediaGenerationModel model;

    setUp(() {
      final apiKey = Platform.environment['GEMINI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw StateError('GEMINI_API_KEY environment variable not set');
      }
      provider = GoogleProvider(apiKey: apiKey);
      model = provider.createMediaModel(name: 'gemini-2.5-flash-image');
    });

    test('generates an image', () async {
      final stream = model.generateMediaStream(
        'Create an image of a futuristic city with flying cars',
        mimeTypes: ['image/png'],
        options: const GoogleMediaGenerationModelOptions(
          imageSampleCount: 1,
          responseModalities: ['TEXT', 'IMAGE'],
        ),
      );

      final results = await stream.toList();
      expect(results, isNotEmpty);

      final result = results.firstWhere(
        (r) => r.assets.isNotEmpty,
        orElse: () => fail('No image generated'),
      );

      expect(result.assets, isNotEmpty);
      final asset = result.assets.first as DataPart;
      expect(asset.mimeType, equals('image/png'));
      expect(asset.bytes, isNotEmpty);
    });
  });
}
