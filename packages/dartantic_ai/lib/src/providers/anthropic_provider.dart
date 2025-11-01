import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../agent/orchestrators/default_streaming_orchestrator.dart';
import '../agent/orchestrators/streaming_orchestrator.dart';
import '../chat_models/anthropic_chat/anthropic_chat.dart';
import '../chat_models/anthropic_chat/anthropic_typed_output_orchestrator.dart';
import '../chat_models/chat_utils.dart';
import '../media_models/anthropic/anthropic_media_model.dart';
import '../media_models/anthropic/anthropic_media_model_options.dart';
import '../platform/platform.dart';
import '../retry_http_client.dart';
import 'chat_orchestrator_provider.dart';

/// Provider for Anthropic Claude native API.
class AnthropicProvider
    extends
        Provider<
          AnthropicChatOptions,
          EmbeddingsModelOptions,
          AnthropicMediaModelOptions
        >
    implements ChatOrchestratorProvider {
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
        defaultModelNames: {
          ModelKind.chat: 'claude-sonnet-4-0',
          ModelKind.media: 'claude-sonnet-4-5',
        },
        caps: {
          ProviderCaps.chat,
          ProviderCaps.multiToolCalls,
          ProviderCaps.typedOutput,
          ProviderCaps.typedOutputWithTools,
          ProviderCaps.chatVision,
          ProviderCaps.thinking,
          ProviderCaps.mediaGeneration,
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
    bool enableThinking = false,
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
      enableThinking: enableThinking,
      apiKey: apiKey!,
      baseUrl: baseUrl,
      defaultOptions: AnthropicChatOptions(
        temperature: temperature ?? options?.temperature,
        topP: options?.topP,
        topK: options?.topK,
        maxTokens: options?.maxTokens,
        stopSequences: options?.stopSequences,
        userId: options?.userId,
        thinkingBudgetTokens: options?.thinkingBudgetTokens,
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
    final client = RetryHttpClient(inner: http.Client());

    try {
      final response = await client.get(
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
    } finally {
      client.close();
    }
  }

  /// The name of the return_result tool.
  static const kAnthropicReturnResultTool = 'return_result';

  @override
  (StreamingOrchestrator, List<Tool>?) getChatOrchestratorAndTools({
    required JsonSchema? outputSchema,
    required List<Tool>? tools,
  }) => (
    outputSchema == null
        ? const DefaultStreamingOrchestrator()
        : const AnthropicTypedOutputOrchestrator(),
    _toolsToUse(outputSchema: outputSchema, tools: tools),
  );

  // If outputSchema is provided, add the return_result tool to the tools list
  // otherwise return the tools list unchanged. The return_result tool is
  // required for typed output and it's what the orchestrator will use to
  // return the final result.
  static List<Tool>? _toolsToUse({
    required JsonSchema? outputSchema,
    required List<Tool>? tools,
  }) {
    if (outputSchema == null) return tools;

    // Check for tool name collision
    if (tools?.any((t) => t.name == kAnthropicReturnResultTool) ?? false) {
      throw ArgumentError(
        'Tool name "$kAnthropicReturnResultTool" is reserved by '
        'Anthropic provider for typed output. '
        'Please use a different tool name.',
      );
    }

    return [
      ...?tools,
      Tool<Map<String, dynamic>>(
        name: kAnthropicReturnResultTool,
        description:
            'REQUIRED: You MUST call this tool to return the final result. '
            'Use this tool to format and return your response according to '
            'the specified JSON schema. Call this after gathering any '
            'necessary information from other tools.',
        inputSchema: outputSchema,
        onCall: (input) async => input,
      ),
    ];
  }

  @override
  MediaGenerationModel<AnthropicMediaModelOptions> createMediaModel({
    String? name,
    List<Tool>? tools,
    AnthropicMediaModelOptions? options,
  }) {
    if (apiKeyName != null && (apiKey == null || apiKey!.isEmpty)) {
      throw ArgumentError('$apiKeyName is required for $displayName provider');
    }

    final modelName =
        name ??
        defaultModelNames[ModelKind.media] ??
        defaultModelNames[ModelKind.chat]!;
    final resolvedOptions = options ?? const AnthropicMediaModelOptions();

    _logger.info(
      'Creating Anthropic media model: $modelName with '
      '${tools?.length ?? 0} tools',
    );

    final chatOptions = AnthropicMediaModel.buildChatOptions(resolvedOptions);
    const betaFeatures = ['code-execution-2025-08-25', 'files-api-2025-04-14'];

    final chatModel = AnthropicChatModel(
      name: modelName,
      tools: tools,
      apiKey: apiKey!,
      baseUrl: baseUrl,
      defaultOptions: chatOptions,
      betaFeatures: betaFeatures,
    );

    return AnthropicMediaModel(
      name: modelName,
      defaultOptions: resolvedOptions,
      chatModel: chatModel,
      apiKey: apiKey!,
      baseUrl: baseUrl,
      betaFeatures: betaFeatures,
    );
  }
}
