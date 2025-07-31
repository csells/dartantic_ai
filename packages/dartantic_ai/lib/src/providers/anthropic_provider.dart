import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../chat_models/anthropic_chat/anthropic_chat.dart';
import '../chat_models/chat_utils.dart';
import '../platform/platform.dart';

/// Provider for Anthropic Claude native API.
class AnthropicProvider
    extends Provider<AnthropicChatOptions, EmbeddingsModelOptions> {
  /// Creates a new Anthropic provider instance.
  ///
  /// [apiKey]: The API key to use for the Anthropic API.
  AnthropicProvider({String? apiKey})
    : super(
        apiKey:
            apiKey ??
            tryGetEnv(_defaultApiTestKeyName) ??
            tryGetEnv(defaultApiKeyName),
        apiKeyName: defaultApiKeyName,
        name: 'anthropic',
        displayName: 'Anthropic',
        defaultModelNames: {ModelKind.chat: 'claude-3-5-sonnet-20241022'},
        caps: {
          ProviderCaps.chat,
          ProviderCaps.multiToolCalls,
          ProviderCaps.typedOutput,
          ProviderCaps.typedOutputWithTools,
          ProviderCaps.vision,
        },
        aliases: ['claude'],
        baseUrl: null,
      );

  static final Logger _logger = Logger('dartantic.chat.providers.anthropic');
  static const _defaultApiTestKeyName = 'ANTHROPIC_API_TEST_KEY';

  /// The default base URL to use unless another is specified.
  static final defaultBaseUrl = Uri.parse('https://api.anthropic.com/v1');

  /// The environment variable for the API key
  static const defaultApiKeyName = 'ANTHROPIC_API_KEY';

  @override
  ChatModel<AnthropicChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    AnthropicChatOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;

    _logger.info(
      'Creating Anthropic model: '
      '$modelName with ${tools?.length ?? 0} tools, temp: $temperature',
    );

    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    return AnthropicChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      apiKey: apiKey!,
      baseUrl: baseUrl,
      defaultOptions: AnthropicChatOptions(
        temperature: temperature ?? options?.temperature,
        topP: options?.topP,
        topK: options?.topK,
        maxTokens: options?.maxTokens,
        stopSequences: options?.stopSequences,
        userId: options?.userId,
      ),
    );
  }

  @override
  EmbeddingsModel<EmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    EmbeddingsModelOptions? options,
  }) => throw Exception('Anthropic does not support embeddings models');

  @override
  Stream<ModelInfo> listModels() async* {
    final resolvedBaseUrl = baseUrl ?? defaultBaseUrl;
    final url = appendPath(resolvedBaseUrl, 'models');
    final response = await http.get(
      url,
      headers: {'x-api-key': apiKey!, 'anthropic-version': '2023-06-01'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch Anthropic models: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final modelsList = data['data'] as List?;
    if (modelsList == null) {
      throw Exception('Anthropic API response missing "data" field.');
    }

    for (final m in modelsList.cast<Map<String, dynamic>>()) {
      final id = m['id'] as String? ?? '';
      final displayName = m['display_name'] as String?;
      final kind = id.startsWith('claude') ? ModelKind.chat : ModelKind.other;
      // Only include extra fields not mapped to ModelInfo
      final extra = <String, dynamic>{
        if (m.containsKey('created_at')) 'createdAt': m['created_at'],
        if (m.containsKey('type')) 'type': m['type'],
      };
      yield ModelInfo(
        name: id,
        providerName: name,
        kinds: {kind},
        displayName: displayName,
        description: null,
        extra: extra,
      );
    }
  }
}
