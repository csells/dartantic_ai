import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../chat_models/chat_utils.dart';
import '../chat_models/openai_responses/openai_responses_chat_model.dart';
import '../chat_models/openai_responses/openai_responses_chat_options.dart';
import '../embeddings_models/openai_embeddings/openai_embeddings.dart';
import '../platform/platform.dart';

/// Provider for OpenAI Responses API.
class OpenAIResponsesProvider
    extends Provider<OpenAIResponsesChatOptions, OpenAIEmbeddingsModelOptions> {
  /// Creates a new OpenAI Responses provider instance.
  ///
  /// [apiKey]: The API key to use for the OpenAI Responses API.
  OpenAIResponsesProvider({
    String? apiKey,
    super.name = 'openai-responses',
    super.displayName = 'OpenAI (Responses API)',
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
      ProviderCaps.thinking,
    },
    super.baseUrl,
    super.apiKeyName = 'OPENAI_API_KEY',
    super.aliases = const ['oai-resp', 'openai-v2'],
  }) : super(apiKey: apiKey ?? tryGetEnv(apiKeyName));

  static final Logger _logger = Logger(
    'dartantic.chat.providers.openai_responses',
  );

  /// The default base URL for the OpenAI API.
  static final defaultBaseUrl = Uri.parse('https://api.openai.com/v1');

  @override
  ChatModel<OpenAIResponsesChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    OpenAIResponsesChatOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    _logger.info(
      'Creating OpenAI Responses model: $modelName with '
      '${tools?.length ?? 0} tools, temperature: $temperature',
    );

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    return OpenAIResponsesChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      apiKey: apiKey ?? tryGetEnv(apiKeyName),
      baseUrl: baseUrl,
      defaultOptions: OpenAIResponsesChatOptions(
        temperature: temperature ?? options?.temperature,
        topP: options?.topP,
        maxTokens: options?.maxTokens,
        seed: options?.seed,
        stop: options?.stop,
        // Encourage robust tool behavior by default
        parallelToolCalls: options?.parallelToolCalls ?? true,
        responseFormat: options?.responseFormat,
        user: options?.user,
        toolChoice: options?.toolChoice ?? 'auto',
        reasoningEffort: options?.reasoningEffort,
        reasoningSummary: options?.reasoningSummary,
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
      'Creating OpenAI embeddings model (with Responses provider): $modelName',
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
    _logger.info('Fetching models from OpenAI API (Responses provider)');

    final resolvedBaseUrl = baseUrl ?? defaultBaseUrl;
    final url = appendPath(resolvedBaseUrl, 'models');
    final headers = <String, String>{
      if (apiKey != null && apiKey!.isNotEmpty)
        'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };

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
          // Heuristics
          if (id.contains('embedding')) kinds.add(ModelKind.embeddings);
          if (id.contains('image')) kinds.add(ModelKind.image);
          if (id.contains('audio')) kinds.add(ModelKind.audio);
          if (id.contains('count-tokens')) kinds.add(ModelKind.countTokens);
          if (object == 'model' ||
              id.contains('gpt') ||
              id.contains('o3') ||
              id.contains('o4') ||
              id.contains('chat')) {
            kinds.add(ModelKind.chat);
          }
          if (kinds.isEmpty) kinds.add(ModelKind.other);
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

      if (data is List) {
        yield* mapModels(data);
      } else if (data is Map<String, dynamic>) {
        final modelsList = data['data'] as List?;
        if (modelsList == null) {
          throw Exception('No models found in response: ${response.body}');
        }
        yield* mapModels(modelsList);
      } else {
        throw Exception('Unexpected models response shape: ${response.body}');
      }
    } catch (e) {
      _logger.warning('Error fetching models from OpenAI API: $e');
      rethrow;
    }
  }
}
