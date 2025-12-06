import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_ai/src/media_gen_models/anthropic/anthropic_files_client.dart';
import 'package:dartantic_ai/src/media_gen_models/anthropic/anthropic_tool_deliverable_tracker.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _NeverHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw StateError('HTTP should not be invoked in unit tests.');
  }
}

void main() {
  group('Media model metadata consistency', () {
    test('Anthropic media mapping includes standard metadata', () async {
      final tracker = AnthropicToolDeliverableTracker(
        AnthropicFilesClient(
          apiKey: 'fake',
          betaFeatures: const [],
          client: _NeverHttpClient(),
        ),
        targetMimeTypes: {'application/pdf'},
      );

      final chatModel = AnthropicChatModel(
        name: 'anthropic',
        apiKey: 'fake',
        client: _NeverHttpClient(),
      );

      final model = AnthropicMediaGenerationModel(
        name: 'anthropic',
        defaultOptions: const AnthropicMediaGenerationModelOptions(),
        chatModel: chatModel,
        apiKey: 'fake',
        httpClient: _NeverHttpClient(),
      );

      final result = await model.mapChunkForTest(
        ChatResult<ChatMessage>(
          output: ChatMessage.model('output'),
          messages: const [
            ChatMessage(
              role: ChatMessageRole.model,
              parts: [TextPart('hello')],
            ),
          ],
          finishReason: FinishReason.unspecified,
        ),
        tracker,
        requestedMimeTypes: const ['application/pdf'],
        chunkIndex: 2,
      );

      expect(result.metadata['generation_mode'], 'code_execution');
      expect(result.metadata['requested_mime_types'], ['application/pdf']);
      expect(result.metadata['chunk_index'], 2);

      model.dispose();
    });

    test('OpenAI Responses media mapping includes standard metadata', () {
      final chatModel = OpenAIResponsesChatModel(
        name: 'openai',
        defaultOptions: const OpenAIResponsesChatModelOptions(),
        apiKey: 'fake',
        httpClient: _NeverHttpClient(),
      );

      final model = OpenAIResponsesMediaGenerationModel(
        name: 'gpt-image',
        defaultOptions: const OpenAIResponsesMediaGenerationModelOptions(),
        chatModel: chatModel,
      );

      final result = model.mapChunkForTest(
        ChatResult<ChatMessage>(
          output: ChatMessage.model('output'),
          messages: const [
            ChatMessage(
              role: ChatMessageRole.model,
              parts: [TextPart('hello')],
            ),
          ],
          finishReason: FinishReason.unspecified,
        ),
        generationMode: 'image_generation',
        requestedMimeTypes: const ['image/png'],
        chunkIndex: 3,
        accumulatedMessages: const [],
      );

      expect(result.metadata['generation_mode'], 'image_generation');
      expect(result.metadata['requested_mime_types'], ['image/png']);
      expect(result.metadata['chunk_index'], 3);

      model.dispose();
    });
  });
}
