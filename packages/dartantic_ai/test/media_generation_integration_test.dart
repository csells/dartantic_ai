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
      requiredCaps: {ProviderCaps.mediaGeneration},
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
      requiredCaps: {ProviderCaps.mediaGeneration},
      timeout: const Timeout(Duration(minutes: 2)),
    );

    runProviderTest(
      'creates PDF artifact using server-side tools',
      (provider) async {
        final agent = Agent(provider.name);

        final result = await agent.generateMedia(
          'Using your available tools, generate a concise PDF named '
          '"summary.pdf" that outlines three key facts about the Dart '
          'programming language.',
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
      requiredCaps: {ProviderCaps.mediaGeneration},
      skipProviders: {'google'},
      timeout: const Timeout(Duration(minutes: 2)),
    );

    runProviderTest(
      'produces downloadable code artifact',
      (provider) async {
        final agent = Agent(provider.name);

        final result = await agent.generateMedia(
          'Write a short README.txt file that explains how to run a Dart '
          'Hello World program. Provide the README as a file asset.',
          mimeTypes: const ['text/plain'],
        );

        final textAssets = result.assets.whereType<DataPart>().where(
          (asset) => asset.mimeType.contains('text'),
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
      requiredCaps: {ProviderCaps.mediaGeneration},
      skipProviders: {'google'},
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
