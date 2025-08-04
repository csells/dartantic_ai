import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../chat_models/chat_utils.dart';
import '../chat_models/openai_chat/openai_chat_model.dart';
import '../chat_models/openai_chat/openai_chat_options.dart';
import '../embeddings_models/openai_embeddings/openai_embeddings.dart';
import '../platform/platform.dart';

/// Provider for OpenAI-compatible APIs (OpenAI, Cohere, Together, etc.).
/// Handles API key, base URL, and model configuration.
class OpenAIProvider
    extends Provider<OpenAIChatOptions, OpenAIEmbeddingsModelOptions> {
  /// Creates a new OpenAI provider instance.
  ///
  /// - [name]: The canonical provider name (e.g., 'openai', 'cohere').
  /// - [displayName]: Human-readable name for display.
  /// - [defaultModelNames]: The default model for this provider.
  /// - [baseUrl]: The default API endpoint.
  /// - [apiKeyName]: The environment variable for the API key (if any).
  /// - [apiKey]: The API key for the OpenAI provider
  OpenAIProvider({
    String? apiKey,
    super.name = 'openai',
    super.displayName = 'OpenAI',
    super.defaultModelNames = const {
      ModelKind.chat: 'gpt-4o',
      ModelKind.embeddings: 'text-embedding-3-small',
    },
    super.caps = const {
      ProviderCaps.chat,
      ProviderCaps.embeddings,
      ProviderCaps.multiToolCalls,
      ProviderCaps.typedOutput,
      ProviderCaps.typedOutputWithTools,
      ProviderCaps.vision,
    },
    super.baseUrl,
    super.apiKeyName = 'OPENAI_API_KEY',
    super.aliases,
  }) : super(apiKey: apiKey ?? tryGetEnv(apiKeyName));

  static final Logger _logger = Logger('dartantic.chat.providers.openai');

  /// The environment variable for the API key
  static const defaultApiKeyName = 'OPENAI_API_KEY';

  /// The default base URL for the OpenAI API.
  static final defaultBaseUrl = Uri.parse('https://api.openai.com/v1');

  @override
  ChatModel<OpenAIChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    OpenAIChatOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    _logger.info(
      'Creating OpenAI model: $modelName with '
      '${tools?.length ?? 0} tools, '
      'temperature: $temperature',
    );

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    return OpenAIChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      apiKey: apiKey ?? tryGetEnv(apiKeyName),
      baseUrl: baseUrl,
      defaultOptions: OpenAIChatOptions(
        temperature: temperature ?? options?.temperature,
        topP: options?.topP,
        n: options?.n,
        maxTokens: options?.maxTokens,
        presencePenalty: options?.presencePenalty,
        frequencyPenalty: options?.frequencyPenalty,
        logitBias: options?.logitBias,
        stop: options?.stop,
        user: options?.user,
        responseFormat: options?.responseFormat,
        seed: options?.seed,
        parallelToolCalls: options?.parallelToolCalls,
        streamOptions: options?.streamOptions,
        serviceTier: options?.serviceTier,
      ),
    );
  }

  @override
  EmbeddingsModel<OpenAIEmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    OpenAIEmbeddingsModelOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.embeddings]!;

    _logger.info(
      'Creating OpenAI embeddings model: $modelName with '
      'options: $options',
    );

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    return OpenAIEmbeddingsModel(
      name: modelName,
      apiKey: apiKey ?? tryGetEnv(apiKeyName),
      baseUrl: baseUrl,
      dimensions: options?.dimensions,
      batchSize: options?.batchSize,
      user: options?.user,
      options: options,
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    _logger.info(
      'Fetching models from OpenAI API: ${baseUrl ?? 'null'}/models',
    );

    final resolvedBaseUrl = baseUrl ?? defaultBaseUrl;
    final url = appendPath(resolvedBaseUrl, 'models');
    final headers = <String, String>{
      if (apiKey != null && apiKey!.isNotEmpty)
        'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };

    _logger.info('Constructed URL: $url');

    try {
      final response = await http.get(url, headers: headers);
      if (response.statusCode != 200) {
        _logger.warning(
          'Failed to fetch models: HTTP ${response.statusCode}, '
          'body: ${response.body}',
        );
        throw Exception('Failed to fetch models: ${response.body}');
      }

      final data = jsonDecode(response.body);

      Stream<ModelInfo> mapModels(Iterable mList) async* {
        for (final m in mList) {
          // ignore: avoid_dynamic_calls
          final id = m['id'] as String;
          final kinds = <ModelKind>{};
          // ignore: avoid_dynamic_calls
          final object = m['object']?.toString() ?? '';
          // Heuristics for OpenAI model kinds
          if (id.contains('embedding')) kinds.add(ModelKind.embeddings);
          if (id.contains('tts')) kinds.add(ModelKind.tts);
          if (id.contains('vision') ||
              id.contains('dall-e') ||
              id.contains('image')) {
            kinds.add(ModelKind.image);
          }
          if (id.contains('audio')) kinds.add(ModelKind.audio);
          if (id.contains('count-tokens')) kinds.add(ModelKind.countTokens);
          // Most models are chat if not otherwise classified
          if (object == 'model' ||
              id.contains('gpt') ||
              id.contains('chat') ||
              id.contains('claude') ||
              id.contains('mixtral') ||
              id.contains('llama') ||
              id.contains('command') ||
              id.contains('sonnet')) {
            kinds.add(ModelKind.chat);
          }
          if (kinds.isEmpty) kinds.add(ModelKind.other);
          assert(kinds.isNotEmpty, 'Model $id returned with empty kinds set');
          yield ModelInfo(
            name: id,
            providerName: name,
            kinds: kinds,
            description: object.isNotEmpty ? object : null,
            extra: {
              ...m,
              // ignore: avoid_dynamic_calls
              if (m.containsKey('context_window'))
                // ignore: avoid_dynamic_calls
                'contextWindow': m['context_window'],
            }..removeWhere((k, _) => ['id', 'object'].contains(k)),
          );
        }
      }

      var modelCount = 0;
      if (data is List) {
        modelCount = data.length;
        yield* mapModels(data);
      } else if (data is Map<String, dynamic>) {
        final modelsList = data['data'] as List?;
        if (modelsList == null) {
          throw Exception('No models found in response: ${response.body}');
        }
        modelCount = modelsList.length;
        yield* mapModels(modelsList);
      } else {
        throw Exception('Unexpected models response shape: ${response.body}');
      }

      _logger.info('Successfully fetched $modelCount models from OpenAI API');
    } catch (e) {
      _logger.warning('Error fetching models from OpenAI API: $e');
      rethrow;
    }
  }
}
