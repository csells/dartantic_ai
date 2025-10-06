import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../embeddings_models/openai_embeddings/openai_embeddings_model.dart';
import '../embeddings_models/openai_embeddings/openai_embeddings_model_options.dart';
import '../platform/platform.dart';
import '../shared/openai_utils.dart';

/// Shared OpenAI provider functionality for canonical and Responses variants.
abstract class OpenAIProviderBase<TChatOptions extends ChatModelOptions>
    extends Provider<TChatOptions, OpenAIEmbeddingsModelOptions> {
  OpenAIProviderBase({
    required super.name,
    required super.displayName,
    required super.defaultModelNames,
    required super.caps,
    super.baseUrl,
    super.apiKeyName,
    super.apiKey,
    super.aliases,
  });

  /// Logger used by subclasses for shared operations.
  Logger get logger;

  /// Base URL used when an explicit embeddings endpoint is not provided.
  Uri get defaultRestBaseUrl => Uri.parse('https://api.openai.com/v1');

  /// Resolved base URL for embeddings API calls.
  ///
  /// Subclasses may override to point at a different endpoint than [baseUrl].
  @protected
  Uri get embeddingsApiBaseUrl => baseUrl ?? defaultRestBaseUrl;

  /// Resolved base URL for listing models.
  @protected
  Uri get modelsApiBaseUrl => baseUrl ?? defaultRestBaseUrl;

  @override
  EmbeddingsModel<OpenAIEmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    OpenAIEmbeddingsModelOptions? options,
  }) {
    validateApiKeyPresence();

    final modelName = name ?? defaultModelNames[ModelKind.embeddings]!;
    logger.info('Creating $displayName embeddings model: $modelName');

    final resolvedOptions = OpenAIEmbeddingsModelOptions(
      dimensions: options?.dimensions,
      batchSize: options?.batchSize,
      user: options?.user,
    );

    return OpenAIEmbeddingsModel(
      name: modelName,
      apiKey: apiKey,
      baseUrl: embeddingsApiBaseUrl,
      dimensions: options?.dimensions,
      batchSize: options?.batchSize,
      options: resolvedOptions,
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    validateApiKeyPresence();
    yield* OpenAIUtils.listOpenAIModels(
      baseUrl: modelsApiBaseUrl,
      providerName: name,
      logger: logger,
      apiKey: apiKey,
    );
  }

  /// Throws if an API key is required but missing.
  @protected
  void validateApiKeyPresence() {
    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }
  }
}
