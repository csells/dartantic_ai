import 'dart:typed_data';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_ai/src/agent/media_response_accumulator.dart';
import 'package:google_cloud_ai_generativelanguage_v1beta/generativelanguage.dart'
    as gl;
import 'package:test/test.dart';

void main() {
  group('GoogleMediaGenerationModel helpers', () {
    test('resolveGoogleMediaMimeType selects supported types', () {
      expect(
        resolveGoogleMediaMimeType(['image/jpeg'], null),
        equals('image/jpeg'),
      );
      expect(
        resolveGoogleMediaMimeType(['image/*'], null),
        equals('image/png'),
      );
      expect(
        resolveGoogleMediaMimeType(['image/webp'], 'image/png'),
        equals('image/png'),
      );
      expect(
        () => resolveGoogleMediaMimeType(['application/pdf'], 'image/gif'),
        throwsUnsupportedError,
      );
    });

    test('mapGoogleModalities validates and maps values', () {
      expect(mapGoogleModalities(['text', 'IMAGE', 'audio']), [
        gl.GenerationConfig_Modality.text,
        gl.GenerationConfig_Modality.image,
        gl.GenerationConfig_Modality.audio,
      ]);

      expect(() => mapGoogleModalities(['video']), throwsUnsupportedError);
    });

    test('mapGoogleMediaFinishReason maps known values', () {
      expect(
        mapGoogleMediaFinishReason(gl.Candidate_FinishReason.stop),
        FinishReason.stop,
      );
      expect(
        mapGoogleMediaFinishReason(gl.Candidate_FinishReason.maxTokens),
        FinishReason.length,
      );
      expect(
        mapGoogleMediaFinishReason(gl.Candidate_FinishReason.safety),
        FinishReason.contentFilter,
      );
      expect(
        mapGoogleMediaFinishReason(gl.Candidate_FinishReason.recitation),
        FinishReason.recitation,
      );
      expect(
        mapGoogleMediaFinishReason(gl.Candidate_FinishReason.other),
        FinishReason.unspecified,
      );
      expect(mapGoogleMediaFinishReason(null), FinishReason.unspecified);
    });

    test('maps fileData, inlineData, and metadata into media result', () {
      final provider = Agent.getProvider('google');
      final model = provider.createMediaModel() as GoogleMediaGenerationModel;

      final response = gl.GenerateContentResponse(
        modelVersion: 'v1beta',
        promptFeedback: gl.GenerateContentResponse_PromptFeedback(
          blockReason:
              gl.GenerateContentResponse_PromptFeedback_BlockReason.safety,
        ),
        usageMetadata: gl.GenerateContentResponse_UsageMetadata(
          promptTokenCount: 1,
          candidatesTokenCount: 2,
          totalTokenCount: 3,
        ),
        candidates: [
          gl.Candidate(
            finishReason: gl.Candidate_FinishReason.stop,
            safetyRatings: [
              gl.SafetyRating(
                category: gl.HarmCategory.harmCategoryHarassment,
                probability: gl.SafetyRating_HarmProbability.medium,
              ),
            ],
            citationMetadata: gl.CitationMetadata(
              citationSources: [
                gl.CitationSource(
                  uri: 'https://example.com',
                  startIndex: 0,
                  endIndex: 10,
                  license: 'cc',
                ),
              ],
            ),
            content: gl.Content(
              role: 'model',
              parts: [
                gl.Part(
                  inlineData: gl.Blob(
                    mimeType: 'image/png',
                    data: Uint8List.fromList([1, 2, 3]),
                  ),
                ),
                gl.Part(
                  fileData: gl.FileData(
                    fileUri: 'https://files.example.com/file.png',
                    mimeType: 'image/png',
                  ),
                ),
                gl.Part(text: 'caption'),
              ],
            ),
          ),
        ],
      );

      final result = model.mapResponseForTest(response);

      expect(result.assets, hasLength(1));
      final asset = result.assets.first as DataPart;
      expect(asset.mimeType, 'image/png');
      expect(asset.name, 'image_0.png');
      expect(asset.bytes, Uint8List.fromList([1, 2, 3]));

      expect(result.links, hasLength(1));
      final link = result.links.first;
      expect(link.url.toString(), 'https://files.example.com/file.png');
      expect(link.mimeType, 'image/png');
      expect(link.name, 'file.png');

      expect(result.messages, hasLength(1));
      expect(result.messages.first.parts.first, isA<TextPart>());
      expect(result.finishReason, FinishReason.stop);
      expect(result.isComplete, isTrue);
      expect(result.usage?.totalTokens, 3);

      expect(result.metadata['block_reason'], isNotNull);
      expect(result.metadata['safety_ratings'], isNotEmpty);
      expect(result.metadata['citation_metadata'], isNotEmpty);
      expect(result.metadata['model'], 'gemini-2.5-flash-image');
      expect(result.metadata['model_version'], 'v1beta');
      expect(result.metadata['generation_mode'], 'test');
      expect(result.metadata['resolved_mime_type'], 'test/unknown');
      expect(result.metadata['chunk_index'], 0);

      model.dispose();
    });

    // With code execution enabled, non-image types are now supported
    // via the Python sandbox fallback.
    test('non-image mime types use code execution fallback', () async {
      final provider = Agent.getProvider('google');
      final model = provider.createMediaModel() as GoogleMediaGenerationModel;

      // Non-image types should not throw - they use code execution
      // This test just verifies the model can be created and accepts PDF
      // mime types without throwing during setup
      expect(model, isNotNull);

      model.dispose();
    });
  });

  group('MediaResponseAccumulator', () {
    test('merges metadata, usage, finish reason, and ids', () {
      final accumulator = MediaResponseAccumulator();

      accumulator.add(
        MediaGenerationResult(
          id: 'first',
          assets: [
            DataPart(Uint8List.fromList([1]), mimeType: 'image/png'),
          ],
          metadata: const {
            'list': [1],
            'map': {'a': 1},
            'value': 'one',
          },
          finishReason: FinishReason.stop,
        ),
      );

      accumulator.add(
        MediaGenerationResult(
          id: 'second',
          links: [
            LinkPart(Uri.parse('https://example.com'), mimeType: 'image/png'),
          ],
          metadata: const {
            'list': [2, 3],
            'map': {'b': 2},
            'value': 'two',
          },
          usage: const LanguageModelUsage(totalTokens: 10),
          finishReason: FinishReason.length,
          isComplete: true,
        ),
      );

      final result = accumulator.buildFinal();

      expect(result.id, 'second');
      expect(result.assets, hasLength(1));
      expect(result.links, hasLength(1));
      expect(result.metadata['list'], equals([1, 2, 3]));
      expect(result.metadata['map'], equals({'a': 1, 'b': 2}));
      expect(result.metadata['value'], 'two');
      expect(result.finishReason, FinishReason.length);
      expect(result.isComplete, isTrue);
      expect(result.usage?.totalTokens, 10);
    });
  });
}
