import 'dart:convert';

import 'package:dartantic_ai/src/embeddings_models/openai_responses/openai_responses_embeddings_model.dart';
import 'package:dartantic_ai/src/embeddings_models/openai_responses/openai_responses_embeddings_options.dart';
import 'package:http/http.dart' as http;
import 'package:openai_core/openai_core.dart' as openai;
import 'package:test/test.dart';

class FakeOpenAIClient extends openai.OpenAIClient {
  FakeOpenAIClient(this._responses)
    : _requestCount = 0,
      super(apiKey: 'test', baseUrl: 'https://example.com');

  final List<Map<String, dynamic>> _responses;
  int _requestCount;

  @override
  Future<http.Response> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
  }) async {
    final payload = _responses[_requestCount++];
    return http.Response(jsonEncode(payload), 200);
  }
}

void main() {
  group('OpenAIResponsesEmbeddingsModel', () {
    test('embedQuery maps vectors and usage', () async {
      final fakeClient = FakeOpenAIClient([
        {
          'data': [
            {
              'embedding': [0.1, 0.2, 0.3],
              'index': 0,
            },
          ],
          'model': 'text-embedding-3-small',
          'usage': {'input_tokens': 5, 'output_tokens': 0, 'total_tokens': 5},
        },
      ]);

      final model = OpenAIResponsesEmbeddingsModel(
        name: 'text-embedding-3-small',
        defaultOptions: const OpenAIResponsesEmbeddingsOptions(),
        client: fakeClient,
      );
      addTearDown(model.dispose);

      final result = await model.embedQuery('input');

      expect(result.output, equals([0.1, 0.2, 0.3]));
      expect(result.usage.promptTokens, equals(5));
      expect(result.usage.totalTokens, equals(5));
    });

    test('embedDocuments batches requests when needed', () async {
      final fakeClient = FakeOpenAIClient([
        {
          'data': [
            {
              'embedding': [1.0],
              'index': 0,
            },
          ],
          'model': 'text-embedding-3-small',
          'usage': {'input_tokens': 3, 'output_tokens': 0, 'total_tokens': 3},
        },
        {
          'data': [
            {
              'embedding': [2.0],
              'index': 0,
            },
          ],
          'model': 'text-embedding-3-small',
          'usage': {'input_tokens': 4, 'output_tokens': 0, 'total_tokens': 4},
        },
      ]);

      final model = OpenAIResponsesEmbeddingsModel(
        name: 'text-embedding-3-small',
        defaultOptions: const OpenAIResponsesEmbeddingsOptions(batchSize: 1),
        client: fakeClient,
      );
      addTearDown(model.dispose);

      final result = await model.embedDocuments(['a', 'b']);

      expect(
        result.output,
        equals([
          [1.0],
          [2.0],
        ]),
      );
      expect(result.usage.promptTokens, equals(7));
      expect(result.usage.totalTokens, equals(7));
    });
  });
}
