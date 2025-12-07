import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:mistralai_dart/mistralai_dart.dart';

import 'mistral_embeddings_model_options.dart';

/// Mistral AI embeddings model implementation.
class MistralEmbeddingsModel
    extends EmbeddingsModel<MistralEmbeddingsModelOptions> {
  /// Creates a new Mistral embeddings model.
  MistralEmbeddingsModel({
    required super.name,
    required String apiKey,
    Uri? baseUrl,
    http.Client? client,
    Map<String, String>? headers,
    super.dimensions,
    super.batchSize = 100,
    MistralEmbeddingsModelOptions? options,
  }) : _client = MistralAIClient(
         apiKey: apiKey,
         baseUrl: baseUrl?.toString(),
         client: client,
         headers: headers,
       ),
       super(defaultOptions: options ?? const MistralEmbeddingsModelOptions()) {
    _logger.info(
      'Created Mistral embeddings model: $name '
      '(dimensions: $dimensions, batchSize: $batchSize)',
    );
  }

  static final _logger = Logger('dartantic.embeddings.models.mistral');
  final MistralAIClient _client;

  @override
  Future<EmbeddingsResult> embedQuery(
    String query, {
    MistralEmbeddingsModelOptions? options,
  }) async {
    final queryLength = query.length;

    _logger.fine(
      'Embedding query with Mistral model "$name" '
      '(length: $queryLength)',
    );

    final result = await embedDocuments([query], options: options);

    final queryResult = EmbeddingsResult(
      id: result.id,
      output: result.embeddings.first,
      finishReason: result.finishReason,
      usage: result.usage,
      metadata: result.metadata,
    );

    _logger.info(
      'Mistral embedding query result: '
      '${queryResult.output.length} dimensions, '
      '${queryResult.usage?.totalTokens ?? 0} tokens',
    );

    return queryResult;
  }

  @override
  Future<BatchEmbeddingsResult> embedDocuments(
    List<String> texts, {
    MistralEmbeddingsModelOptions? options,
  }) async {
    final chunks = <List<String>>[];
    final actualBatchSize = options?.batchSize ?? batchSize ?? 100;
    final totalTexts = texts.length;
    final totalCharacters = texts.map((t) => t.length).reduce((a, b) => a + b);

    for (var i = 0; i < texts.length; i += actualBatchSize) {
      chunks.add(
        texts.sublist(i, (i + actualBatchSize).clamp(0, texts.length)),
      );
    }

    _logger.info(
      'Embedding $totalTexts documents with Mistral model "$name" '
      '(batches: ${chunks.length}, batchSize: $actualBatchSize, '
      'totalChars: $totalCharacters)',
    );

    final allEmbeddings = <List<double>>[];
    var totalPromptTokens = 0;
    var totalTokens = 0;
    var lastId = '';

    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final chunkCharacters = chunk
          .map((t) => t.length)
          .reduce((a, b) => a + b);

      _logger.fine(
        'Processing batch ${i + 1}/${chunks.length} '
        '(${chunk.length} texts, $chunkCharacters chars)',
      );

      final result = await _client.createEmbedding(
        request: EmbeddingRequest(
          model: EmbeddingModel.modelId(name),
          input: chunk,
        ),
      );

      allEmbeddings.addAll(result.data.map((e) => e.embedding));

      // Accumulate usage data
      totalPromptTokens += result.usage.promptTokens;
      totalTokens += result.usage.totalTokens;

      lastId = result.id;

      _logger.fine(
        'Batch ${i + 1} completed: '
        '${result.data.length} embeddings, '
        '${result.usage.totalTokens} tokens',
      );
    }

    final usage = LanguageModelUsage(
      promptTokens: totalPromptTokens > 0 ? totalPromptTokens : null,
      totalTokens: totalTokens > 0 ? totalTokens : null,
    );

    final result = BatchEmbeddingsResult(
      id: lastId,
      output: allEmbeddings,
      finishReason: FinishReason.stop,
      usage: usage,
      metadata: {'model': name, 'provider': 'mistral'},
    );

    _logger.info(
      'Mistral batch embedding completed: '
      '${result.output.length} embeddings, '
      '${result.usage?.totalTokens ?? 0} total tokens',
    );

    return result;
  }

  @override
  void dispose() => _client.endSession();
}
