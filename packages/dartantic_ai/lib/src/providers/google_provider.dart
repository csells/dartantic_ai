import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:google_cloud_ai_generativelanguage_v1beta/generativelanguage.dart'
    as gl;
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../agent/orchestrators/default_streaming_orchestrator.dart';
import '../agent/orchestrators/streaming_orchestrator.dart';
import '../chat_models/google_chat/google_chat_model.dart';
import '../chat_models/google_chat/google_chat_options.dart';
import '../chat_models/google_chat/google_double_agent_orchestrator.dart';
import '../custom_http_client.dart';
import '../embeddings_models/google_embeddings/google_embeddings_model.dart';
import '../embeddings_models/google_embeddings/google_embeddings_model_options.dart';
import '../platform/platform.dart';
import '../retry_http_client.dart';
import 'chat_orchestrator_provider.dart';
import 'google_api_utils.dart';

/// Provider for Google Gemini native API.
class GoogleProvider
    extends Provider<GoogleChatModelOptions, GoogleEmbeddingsModelOptions>
    implements ChatOrchestratorProvider {
  /// Creates a new Google AI provider instance.
  ///
  /// [apiKey]: The API key to use for the Google AI API.
  GoogleProvider({String? apiKey, super.baseUrl})
    : super(
        apiKey: apiKey ?? tryGetEnv(defaultApiKeyName),
        apiKeyName: defaultApiKeyName,
        name: 'google',
        displayName: 'Google',
        defaultModelNames: {
          ModelKind.chat: 'gemini-2.5-flash',
          ModelKind.embeddings: 'models/text-embedding-004',
        },
        caps: {
          ProviderCaps.chat,
          ProviderCaps.embeddings,
          ProviderCaps.multiToolCalls,
          ProviderCaps.typedOutput,
          ProviderCaps.typedOutputWithTools,
          ProviderCaps.chatVision,
        },
        aliases: const ['gemini'],
      );

  static final Logger _logger = Logger('dartantic.chat.providers.google');

  /// The default API key name.
  static const defaultApiKeyName = 'GEMINI_API_KEY';

  /// The default base URL for the Google AI API.
  static final defaultBaseUrl = GoogleApiConfig.defaultBaseUrl;

  @override
  (StreamingOrchestrator, List<Tool>?) getChatOrchestratorAndTools({
    required JsonSchema? outputSchema,
    required List<Tool>? tools,
  }) {
    final hasTools = tools != null && tools.isNotEmpty;

    if (outputSchema != null && hasTools) {
      // Double agent: tools + typed output (requires stateful orchestrator)
      return (GoogleDoubleAgentOrchestrator(), tools);
    }

    // Standard cases use default
    return (const DefaultStreamingOrchestrator(), tools);
  }

  @override
  ChatModel<GoogleChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    GoogleChatModelOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    _logger.info(
      'Creating Google model: $modelName with '
      '${tools?.length ?? 0} tools, '
      'temp: $temperature',
    );

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    return GoogleChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      apiKey: apiKey!,
      baseUrl: baseUrl ?? defaultBaseUrl,
      defaultOptions: GoogleChatModelOptions(
        topP: options?.topP,
        topK: options?.topK,
        candidateCount: options?.candidateCount,
        maxOutputTokens: options?.maxOutputTokens,
        temperature: temperature ?? options?.temperature,
        stopSequences: options?.stopSequences,
        responseMimeType: options?.responseMimeType,
        responseSchema: options?.responseSchema,
        safetySettings: options?.safetySettings,
        enableCodeExecution: options?.enableCodeExecution,
      ),
    );
  }

  @override
  EmbeddingsModel<GoogleEmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    GoogleEmbeddingsModelOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.embeddings]!;
    _logger.info('Creating Google model: $modelName');

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    return GoogleEmbeddingsModel(
      name: modelName,
      apiKey: apiKey!,
      baseUrl: baseUrl ?? defaultBaseUrl,
      options: options,
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    final apiKey = this.apiKey ?? getEnv(defaultApiKeyName);
    final resolvedBaseUrl = baseUrl ?? defaultBaseUrl;
    final client = CustomHttpClient(
      baseHttpClient: RetryHttpClient(inner: http.Client()),
      baseUrl: resolvedBaseUrl,
      headers: {'x-goog-api-key': apiKey},
      queryParams: const {},
    );

    final service = gl.ModelService(client: client);
    try {
      String? pageToken;
      do {
        final response = await service.listModels(
          gl.ListModelsRequest(pageSize: 1000, pageToken: pageToken),
        );
        final models = response.models ?? const <gl.Model>[];
        _logger.info(
          'Fetched ${models.length} models from Google API '
          '(pageToken: ${pageToken ?? 'start'})',
        );
        for (final model in models) {
          final info = _mapModel(model);
          if (info != null) yield info;
        }
        pageToken = response.nextPageToken;
      } while (pageToken?.isNotEmpty ?? false);
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to fetch models from Google API',
        error,
        stackTrace,
      );
      rethrow;
    } finally {
      service.close();
    }
  }

  ModelInfo? _mapModel(gl.Model model) {
    final id = model.name;
    if (id == null || id.isEmpty) {
      _logger.warning('Skipping model with missing name: $model');
      return null;
    }

    final description = model.description ?? '';
    final methods = (model.supportedGenerationMethods ?? const [])
        .map((method) => method.toLowerCase())
        .toList(growable: false);

    final kinds = <ModelKind>{};
    if (methods.any((m) => m.contains('embed'))) {
      kinds.add(ModelKind.embeddings);
    }
    if (methods.any(
      (m) => m.contains('generatecontent') || m.contains('generatemessage'),
    )) {
      kinds.add(ModelKind.chat);
    }
    if (methods.any((m) => m.contains('generateimage'))) {
      kinds.add(ModelKind.image);
    }
    if (methods.any((m) => m.contains('generateaudio'))) {
      kinds.add(ModelKind.audio);
    }
    if (methods.any(
      (m) => m.contains('generatespeech') || m.contains('generatetts'),
    )) {
      kinds.add(ModelKind.tts);
    }
    if (methods.any((m) => m.contains('counttokens'))) {
      kinds.add(ModelKind.countTokens);
    }

    final lowerId = id.toLowerCase();
    final lowerBase = (model.baseModelId ?? '').toLowerCase();
    final lowerDescription = description.toLowerCase();

    bool contains(String value) =>
        lowerId.contains(value) ||
        lowerBase.contains(value) ||
        lowerDescription.contains(value);

    if (kinds.isEmpty) {
      if (contains('embed')) kinds.add(ModelKind.embeddings);
      if (contains('vision') || contains('image')) kinds.add(ModelKind.image);
      if (contains('tts')) kinds.add(ModelKind.tts);
      if (contains('audio')) kinds.add(ModelKind.audio);
      if (contains('count-tokens') || contains('count tokens')) {
        kinds.add(ModelKind.countTokens);
      }
      if (contains('gemini') || contains('chat')) kinds.add(ModelKind.chat);
    }

    if (kinds.isEmpty) kinds.add(ModelKind.other);

    final extra = <String, dynamic>{
      if (model.baseModelId != null) 'baseModelId': model.baseModelId,
      if (model.version != null) 'version': model.version,
      if (model.inputTokenLimit != null) 'contextWindow': model.inputTokenLimit,
      if (model.outputTokenLimit != null)
        'outputTokenLimit': model.outputTokenLimit,
      if (model.supportedGenerationMethods != null)
        'supportedGenerationMethods': model.supportedGenerationMethods,
      if (model.temperature != null) 'temperature': model.temperature,
      if (model.maxTemperature != null) 'maxTemperature': model.maxTemperature,
      if (model.topP != null) 'topP': model.topP,
      if (model.topK != null) 'topK': model.topK,
    };

    return ModelInfo(
      name: id,
      providerName: name,
      kinds: kinds,
      displayName: model.displayName,
      description: description.isNotEmpty ? description : null,
      extra: extra,
    );
  }
}
