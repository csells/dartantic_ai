import 'package:dartantic_ai/dartantic_ai.dart';

import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';

void main() {
  group('Media Generation Integration', () {
    runProviderTest(
      'produces media output for basic prompt',
      (provider) async {
        final agent = Agent(provider.name);

        final result = await agent.generateMedia(
          'Generate a tiny minimalist black-and-white logo of a circle.',
          mimeTypes: const ['image/png'],
        );

        expect(
          result.assets.isNotEmpty || result.links.isNotEmpty,
          isTrue,
          reason: 'Provider ${provider.name} should return at least one asset',
        );

        // Assets return as binary data; links return remote URIs.
        for (final asset in result.assets) {
          expect(asset, isA<DataPart>());
          expect((asset as DataPart).bytes.isNotEmpty, isTrue);
          expect(asset.mimeType.startsWith('image/'), isTrue);
        }
        for (final link in result.links) {
          expect(link.url.hasScheme, isTrue);
        }
      },
      requiredCaps: {ProviderTestCaps.mediaGeneration},
      timeout: const Timeout(Duration(minutes: 2)),
    );

    runProviderTest(
      'streams media results incrementally',
      (provider) async {
        final agent = Agent(provider.name);

        final chunks = await agent
            .generateMediaStream(
              'Create a simple abstract icon consisting of three dots.',
              mimeTypes: const ['image/png'],
            )
            .toList();

        expect(chunks, isNotEmpty);
        final anyAsset = chunks.any((chunk) => chunk.assets.isNotEmpty);
        final anyLink = chunks.any((chunk) => chunk.links.isNotEmpty);
        expect(
          anyAsset || anyLink,
          isTrue,
          reason: 'Provider ${provider.name} should stream media output',
        );
      },
      requiredCaps: {ProviderTestCaps.mediaGeneration},
      timeout: const Timeout(Duration(minutes: 2)),
    );

    runProviderTest(
      'creates PDF artifact using server-side tools',
      (provider) async {
        final agent = Agent(provider.name);

        final result = await agent.generateMedia(
          'Write Python code to create a PDF file called "dart_facts.pdf". '
          'Use the reportlab library. The PDF should contain:\n'
          '- Title: "Dart Programming Language" (18pt bold)\n'
          '- Line 1: "Created by Google in 2011"\n'
          '- Line 2: "Powers the Flutter framework"\n'
          '- Line 3: "Supports AOT and JIT compilation"\n'
          'Save the file and return it.',
          mimeTypes: const ['application/pdf'],
        );

        final pdfAssets = result.assets.whereType<DataPart>().where(
          (asset) => asset.mimeType.contains('pdf'),
        );

        expect(
          pdfAssets.isNotEmpty,
          isTrue,
          reason:
              'Provider ${provider.name} should return at least one PDF asset',
        );

        for (final asset in pdfAssets) {
          expect(asset.bytes.isNotEmpty, isTrue);
        }
      },
      requiredCaps: {ProviderTestCaps.mediaGeneration},
      timeout: const Timeout(Duration(minutes: 2)),
    );

    runProviderTest(
      'produces downloadable code artifact',
      (provider) async {
        final agent = Agent(provider.name);

        // Use a computation-based prompt that reliably triggers code
        // interpreter and produces structured output with proper file
        // citations. Pattern from: example/bin/server_side_tools_openai/
        // server_side_code_interpreter.dart
        final result = await agent.generateMedia(
          'Calculate the first 5 prime numbers and store them in a variable '
          'called "primes". Then create a CSV file called "primes.csv" with '
          'two columns: index and value.',
          mimeTypes: const ['text/csv'],
        );

        final textAssets = result.assets.whereType<DataPart>().where(
          (asset) =>
              asset.mimeType.contains('text') ||
              asset.mimeType.contains('csv') ||
              (asset.name?.endsWith('.csv') ?? false),
        );

        expect(
          textAssets.isNotEmpty,
          isTrue,
          reason:
              'Provider ${provider.name} should return at least one text asset',
        );

        for (final asset in textAssets) {
          expect(asset.bytes.isNotEmpty, isTrue);
          expect(asset.name, isNotNull);
        }
      },
      requiredCaps: {ProviderTestCaps.mediaGeneration},
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
