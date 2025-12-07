import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../chat_models/chat_utils.dart';
import '../chat_models/ollama_chat/ollama_chat_model.dart';
import '../retry_http_client.dart';

/// Provider for native Ollama API (local, not OpenAI-compatible).
class OllamaProvider
    extends
        Provider<
          OllamaChatOptions,
          EmbeddingsModelOptions,
          MediaGenerationModelOptions
        > {
  /// Creates a new Ollama provider instance.
  OllamaProvider({
    super.name = 'ollama',
    super.displayName = 'Ollama',
    super.apiKey,
    super.baseUrl,
    super.apiKeyName,
    super.headers,
  }) : super(
         defaultModelNames: {
           /// Note: llama3.x models have a known issue with spurious content in
           /// tool calling responses, generating unwanted JSON fragments like
           /// '", "parameters": {}}' during streaming. qwen2.5:7b-instruct
           /// provides cleaner tool calling behavior.
           ModelKind.chat: 'qwen2.5:7b-instruct',
         },
         caps: const {ProviderCaps.chat, ProviderCaps.typedOutput},
       );

  static final Logger _logger = Logger('dartantic.chat.providers.ollama');

  /// The default base URL to use unless another is specified.
  static final defaultBaseUrl = Uri.parse('http://localhost:11434/api');

  @override
  ChatModel<OllamaChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    bool enableThinking = false,
    OllamaChatOptions? options,
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
      'Creating Ollama model: $modelName with ${tools?.length ?? 0} tools, '
      'temp: $temperature',
    );

    return OllamaChatModel(
      name: modelName,
      tools: tools,
      temperature: temperature,
      baseUrl: baseUrl,
      headers: headers,
      defaultOptions: OllamaChatOptions(
        format: options?.format,
        keepAlive: options?.keepAlive,
        numKeep: options?.numKeep,
        seed: options?.seed,
        numPredict: options?.numPredict,
        topK: options?.topK,
        topP: options?.topP,
        minP: options?.minP,
        tfsZ: options?.tfsZ,
        typicalP: options?.typicalP,
        repeatLastN: options?.repeatLastN,
        repeatPenalty: options?.repeatPenalty,
        presencePenalty: options?.presencePenalty,
        frequencyPenalty: options?.frequencyPenalty,
        mirostat: options?.mirostat,
        mirostatTau: options?.mirostatTau,
        mirostatEta: options?.mirostatEta,
        penalizeNewline: options?.penalizeNewline,
        stop: options?.stop,
        numa: options?.numa,
        numCtx: options?.numCtx,
        numBatch: options?.numBatch,
        numGpu: options?.numGpu,
        mainGpu: options?.mainGpu,
        lowVram: options?.lowVram,
        f16KV: options?.f16KV,
        logitsAll: options?.logitsAll,
        vocabOnly: options?.vocabOnly,
        useMmap: options?.useMmap,
        useMlock: options?.useMlock,
        numThread: options?.numThread,
      ),
    );
  }

  @override
  EmbeddingsModel<EmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    EmbeddingsModelOptions? options,
  }) => throw Exception('Ollama does not support embeddings models');

  @override
  Stream<ModelInfo> listModels() async* {
    final resolvedBaseUrl = baseUrl ?? defaultBaseUrl;
    final url = appendPath(resolvedBaseUrl, 'tags');
    _logger.info('Fetching models from Ollama API: $url');
    final client = RetryHttpClient(inner: http.Client());
    try {
      final response = await client.get(url, headers: headers);
      if (response.statusCode != 200) {
        _logger.warning(
          'Failed to fetch models: HTTP ${response.statusCode}, '
          'body: ${response.body}',
        );
        throw Exception('Failed to fetch Ollama models: ${response.body}');
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final modelCount = (data['models'] as List).length;
      _logger.info('Successfully fetched $modelCount models from Ollama API');

      // Defensive: ensure 'name' is a String, fallback to '' if not.
      for (final m in (data['models'] as List).cast<Map<String, dynamic>>()) {
        final nameField = m['name'];
        final id = nameField is String ? nameField : '';
        final name = nameField is String ? nameField : null;
        final detailsField = m['details'];
        final description = detailsField is String ? detailsField : null;
        yield ModelInfo(
          name: id,
          providerName: this.name,
          kinds: {ModelKind.chat},
          displayName: name,
          description: description,
          extra: {...m}..removeWhere((k, _) => ['name', 'details'].contains(k)),
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
    throw UnsupportedError('Ollama provider does not support media generation');
  }
}
