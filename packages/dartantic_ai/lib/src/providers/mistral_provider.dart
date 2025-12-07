import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../chat_models/chat_utils.dart';
import '../chat_models/mistral_chat/mistral_chat_model.dart';
import '../chat_models/mistral_chat/mistral_chat_options.dart';
import '../embeddings_models/mistral_embeddings/mistral_embeddings.dart';
import '../platform/platform.dart';
import '../retry_http_client.dart';

/// Provider for Mistral AI (OpenAI-compatible).
class MistralProvider
    extends
        Provider<
          MistralChatModelOptions,
          MistralEmbeddingsModelOptions,
          MediaGenerationModelOptions
        > {
  /// Creates a new Mistral provider instance.
  ///
  /// [apiKey]: The API key for the Mistral provider.
  MistralProvider({String? apiKey, super.headers})
    : super(
        apiKey: apiKey ?? tryGetEnv(defaultApiKeyName),
        name: 'mistral',
        displayName: 'Mistral',
        defaultModelNames: {
          ModelKind.chat: 'open-mistral-7b',
          ModelKind.embeddings: 'mistral-embed',
        },
        caps: const {ProviderCaps.chat, ProviderCaps.embeddings},
        baseUrl: null,
        aliases: ['mistralai'],
      );

  static final Logger _logger = Logger('dartantic.chat.providers.mistral');

  /// The default API key name for Mistral.
  static const defaultApiKeyName = 'MISTRAL_API_KEY';

  /// The default base URL for the Mistral API.
  static final defaultBaseUrl = Uri.parse('https://api.mistral.ai/v1');

  @override
  ChatModel<MistralChatModelOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    MistralChatModelOptions? options,
  }) {
    if (enableThinking) {
      throw UnsupportedError(
        'Extended thinking is not supported by the $displayName provider. '
        'Only OpenAI Responses, Anthropic, and Google providers support '
        'thinking. Set enableThinking=false or use a provider that supports '
        'this feature.',
      );
    }

    final modelName = name ?? defaultModelNames[ModelKind.chat]!;
    _logger.info(
      'Creating Mistral model: $modelName with ${tools?.length ?? 0} tools, '
      'temp: $temperature',
    );

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    return MistralChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      apiKey: apiKey!,
      baseUrl: baseUrl,
      headers: headers,
      defaultOptions: MistralChatModelOptions(
        topP: options?.topP,
        maxTokens: options?.maxTokens,
        safePrompt: options?.safePrompt,
        randomSeed: options?.randomSeed,
      ),
    );
  }

  @override
  EmbeddingsModel<MistralEmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    MistralEmbeddingsModelOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.embeddings]!;
    _logger.info('Creating Mistral embeddings model: $modelName');

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    return MistralEmbeddingsModel(
      name: modelName,
      apiKey: apiKey!,
      baseUrl: baseUrl,
      headers: headers,
      options: options,
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    final resolvedBaseUrl = baseUrl ?? defaultBaseUrl;
    final url = appendPath(resolvedBaseUrl, 'models');
    _logger.info('Fetching models from Mistral API: $url');
    final client = RetryHttpClient(inner: http.Client());
    try {
      final response = await client.get(
        url,
        headers: {'Authorization': 'Bearer $apiKey', ...headers},
      );
      if (response.statusCode != 200) {
        _logger.warning(
          'Failed to fetch models: HTTP ${response.statusCode}, '
          'body: ${response.body}',
        );
        throw Exception('Failed to fetch Mistral models: ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final modelCount = (data['data'] as List).length;
      _logger.info('Successfully fetched $modelCount models from Mistral API');
      for (final m in (data['data'] as List).cast<Map<String, dynamic>>()) {
        final id = m['id'] as String? ?? '';
        final desc = m['description'] as String? ?? '';
        final kinds = <ModelKind>{};
        // Embedding models
        if (id.contains('embed') || desc.contains('embed')) {
          kinds.add(ModelKind.embeddings);
        }
        // Magistral: always chat unless embedding
        if (id.contains('magistral') && !kinds.contains(ModelKind.embeddings)) {
          kinds.add(ModelKind.chat);
        }
        // Mistral, Mixtral, Codestral: chat unless embedding
        if ((id.contains('mistral') ||
                id.contains('mixtral') ||
                id.contains('codestral')) &&
            !id.contains('embed') &&
            !kinds.contains(ModelKind.embeddings)) {
          kinds.add(ModelKind.chat);
        }
        // Moderation and OCR: treat as chat
        if (id.contains('moderation') || id.contains('ocr')) {
          kinds.add(ModelKind.chat);
        }
        // Ministral: not officially documented, mark as other
        if (id.contains('ministral')) {
          kinds
            ..clear()
            ..add(ModelKind.other);
        }

        // Pixtral: not officially documented, mark as other
        if (id.contains('pixtral')) {
          kinds
            ..clear()
            ..add(ModelKind.other);
        }
        if (kinds.isEmpty) kinds.add(ModelKind.other);
        assert(kinds.isNotEmpty, 'Model $id returned with empty kinds set');
        yield ModelInfo(
          name: id,
          providerName: name,
          kinds: kinds,
          displayName: m['name'] as String?,
          description: desc.isNotEmpty ? desc : null,
          extra: {
            ...m,
            if (m.containsKey('context_length'))
              'contextWindow': m['context_length'],
          }..removeWhere((k, _) => ['id', 'name', 'description'].contains(k)),
        );
      }
    } finally {
      client.close();
    }
  }

  @override
  MediaGenerationModel<MediaGenerationModelOptions> createMediaModel({
    String? name,
    List<Tool>? tools,
    MediaGenerationModelOptions? options,
  }) {
    throw UnsupportedError(
      'Mistral provider does not support media generation',
    );
  }
}
