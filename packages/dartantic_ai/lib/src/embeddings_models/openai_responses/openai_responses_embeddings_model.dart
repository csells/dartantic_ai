import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../../retry_http_client.dart';
import '../chunk_list.dart';
import 'openai_responses_embeddings_options.dart';

/// Embeddings model backed by the OpenAI Responses API.
class OpenAIResponsesEmbeddingsModel
    extends EmbeddingsModel<OpenAIResponsesEmbeddingsOptions> {
  /// Creates a new OpenAI Responses embeddings model instance.
  OpenAIResponsesEmbeddingsModel({
    required super.name,
    required super.defaultOptions,
    super.dimensions,
    super.batchSize,
    Uri? baseUrl,
    String? apiKey,
    http.Client? httpClient,
    openai.OpenAIClient? client,
  }) : _client =
           client ??
           openai.OpenAIClient(
             apiKey: apiKey,
             // openai_core requires non-nullable baseUrl, embeddings use
             // standard endpoint
             baseUrl: baseUrl?.toString() ?? 'https://api.openai.com/v1',
             httpClient: RetryHttpClient(inner: httpClient ?? http.Client()),
           );

  static final Logger _logger =
      Logger('dartantic.embeddings.openai_responses');

  final openai.OpenAIClient _client;

  @override
  Future<EmbeddingsResult> embedQuery(
    String query, {
    OpenAIResponsesEmbeddingsOptions? options,
  }) async {
    final effectiveOptions = options ?? defaultOptions;
    final dims = effectiveOptions.dimensions ?? dimensions;

    _logger.fine('Embedding query with "$name" (dimensions: $dims)');

    final result = await _client.createEmbeddings(
      input: query,
      model: openai.EmbeddingModel(name),
      dimensions: dims,
      encodingFormat: effectiveOptions.encodingFormat,
      user: effectiveOptions.user,
    );

    final vector = result.vectors.isEmpty ? <double>[] : result.vectors.first;

    return EmbeddingsResult(
      output: vector,
      finishReason: FinishReason.stop,
      metadata: {'model': name, 'dimensions': vector.length},
      usage: _mapUsage(result.usage),
    );
  }

  @override
  Future<BatchEmbeddingsResult> embedDocuments(
    List<String> texts, {
    OpenAIResponsesEmbeddingsOptions? options,
  }) async {
    if (texts.isEmpty) {
      return BatchEmbeddingsResult(
        output: const [],
        finishReason: FinishReason.stop,
        metadata: {
          'model': name,
          'dimensions': 0,
          'batch_count': 0,
          'total_texts': 0,
        },
        usage: const LanguageModelUsage(),
      );
    }

    final effectiveOptions = options ?? defaultOptions;
    final dims = effectiveOptions.dimensions ?? dimensions;
    final batchSz = effectiveOptions.batchSize ?? batchSize ?? texts.length;

    final batches = chunkList(texts, chunkSize: batchSz);
    final embeddings = <List<double>>[];
    var totalUsage = const LanguageModelUsage();

    for (final batch in batches) {
      final response = await _client.createEmbeddings(
        input: batch.toList(growable: false),
        model: openai.EmbeddingModel(name),
        dimensions: dims,
        encodingFormat: effectiveOptions.encodingFormat,
        user: effectiveOptions.user,
      );

      embeddings.addAll(response.vectors);
      totalUsage = totalUsage.concat(_mapUsage(response.usage));
    }

    return BatchEmbeddingsResult(
      output: embeddings,
      finishReason: FinishReason.stop,
      metadata: {
        'model': name,
        'dimensions': embeddings.isEmpty ? 0 : embeddings.first.length,
        'batch_count': batches.length,
        'total_texts': texts.length,
      },
      usage: totalUsage,
    );
  }

  @override
  void dispose() {
    _client.close();
  }

  static LanguageModelUsage _mapUsage(openai.Usage? usage) => usage == null
      ? const LanguageModelUsage()
      : LanguageModelUsage(
          promptTokens: usage.inputTokens,
          responseTokens: usage.outputTokens,
          totalTokens: usage.totalTokens,
        );
}
