import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../../dartantic_ai.dart';
import '../chat_models/chat_utils.dart';
import '../chat_models/google_chat/google_chat.dart';
import '../platform/platform.dart';

/// Provider for Google Gemini native API.
class GoogleProvider
    extends Provider<GoogleChatModelOptions, GoogleEmbeddingsModelOptions> {
  /// Creates a new Google AI provider instance.
  ///
  /// [apiKey]: The API key to use for the Google AI API.
  GoogleProvider({String? apiKey})
    : super(
        apiKey: apiKey ?? tryGetEnv(defaultApiKeyName),
        apiKeyName: defaultApiKeyName,
        name: 'google',
        displayName: 'Google',
        defaultModelNames: {
          ModelKind.chat: 'gemini-2.0-flash',
          ModelKind.embeddings: 'models/text-embedding-004',
        },
        caps: {
          ProviderCaps.chat,
          ProviderCaps.embeddings,
          ProviderCaps.multiToolCalls,
          ProviderCaps.typedOutput,
          ProviderCaps.vision,
        },
        aliases: ['gemini'],
        baseUrl: null,
      );

  static final Logger _logger = Logger('dartantic.chat.providers.google');

  /// The default API key name.
  static const defaultApiKeyName = 'GEMINI_API_KEY';

  /// The default base URL for the Google AI API.
  static final defaultBaseUrl = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta',
  );

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
      baseUrl: baseUrl,
      options: options,
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    final apiKey = this.apiKey ?? getEnv(defaultApiKeyName);
    final resolvedBaseUrl = baseUrl ?? defaultBaseUrl;
    final url = appendPath(resolvedBaseUrl, 'models');
    _logger.info('Fetching models from Google API: $url');
    final response = await http.get(url, headers: {'x-goog-api-key': apiKey});
    if (response.statusCode != 200) {
      _logger.warning(
        'Failed to fetch models: HTTP ${response.statusCode}, '
        'body: ${response.body}',
      );
      throw Exception('Failed to fetch Gemini models: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final modelCount = (data['models'] as List).length;
    _logger.info('Successfully fetched $modelCount models from Google API');
    for (final m in (data['models'] as List).cast<Map<String, dynamic>>()) {
      final id = m['name'] as String;
      final kinds = <ModelKind>{};
      final desc = m['description'] as String? ?? '';
      // Heuristics for Gemini model kinds
      if (id.contains('embed') || desc.contains('embedding')) {
        kinds.add(ModelKind.embeddings);
      }
      if (id.contains('vision') ||
          desc.contains('vision') ||
          id.contains('image')) {
        kinds.add(ModelKind.image);
      }
      if (id.contains('tts') || desc.contains('tts')) kinds.add(ModelKind.tts);
      if (id.contains('audio') || desc.contains('audio')) {
        kinds.add(ModelKind.audio);
      }
      if (id.contains('count-tokens') || desc.contains('count tokens')) {
        kinds.add(ModelKind.countTokens);
      } // Most Gemini models are chat if not otherwise classified
      if (id.contains('gemini') ||
          id.contains('chat') ||
          desc.contains('chat')) {
        kinds.add(ModelKind.chat);
      }
      if (kinds.isEmpty) kinds.add(ModelKind.other);
      assert(kinds.isNotEmpty, 'Model $id returned with empty kinds set');
      yield ModelInfo(
        name: id,
        providerName: name,
        kinds: kinds,
        displayName: m['displayName'] as String?,
        description: desc.isNotEmpty ? desc : null,
        extra:
            {
              ...m,
              if (m.containsKey('inputTokenLimit'))
                'contextWindow': m['inputTokenLimit'],
            }..removeWhere(
              (k, _) => ['name', 'displayName', 'description'].contains(k),
            ),
      );
    }
  }
}
