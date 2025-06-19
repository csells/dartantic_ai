import 'package:openai_dart/openai_dart.dart' as oai;

import '../../models/implementations/openai_model.dart';
import '../../models/interface/model.dart';
import '../../models/interface/model_settings.dart';
import '../../platform/platform.dart' as platform;
import '../interface/provider.dart';
import '../interface/provider_caps.dart';

/// Provider for OpenAI models.
///
/// This provider creates instances of [OpenAiModel] using the specified
/// model name and API key.
class OpenAiProvider extends Provider {
  /// Creates a new [OpenAiProvider] with the given parameters.
  ///
  /// The [modelName] is the name of the OpenAI model to use.
  /// If not provided, [OpenAiModel.defaultModelName] is used.
  /// The [embeddingModelName] is the name of the OpenAI embedding model to use.
  /// If not provided, [OpenAiModel.defaultEmbeddingModelName] is used.
  /// The [apiKey] is the API key to use for authentication.
  /// If not provided, it's retrieved from the environment.
  OpenAiProvider({
    String? alias,
    this.modelName,
    this.embeddingModelName,
    String? apiKey,
    this.baseUrl,
    this.temperature,
    this.caps = ProviderCaps.all,
  }) : apiKey = apiKey ?? platform.getEnv(apiKeyName),
       _alias = alias;

  /// The name of the environment variable that contains the API key.
  static const apiKeyName = 'OPENAI_API_KEY';

  @override
  String get name => _alias ?? 'openai';

  /// The name of the OpenAI model to use.
  final String? modelName;

  /// The name of the OpenAI embedding model to use.
  final String? embeddingModelName;

  /// The API key to use for authentication with the OpenAI API.
  final String apiKey;

  /// The base URL for the OpenAI API.
  final Uri? baseUrl;

  /// The temperature to use for the OpenAI API.
  final double? temperature;

  final String? _alias;

  /// Creates a [Model] instance using this provider's configuration.
  ///
  /// The [settings] parameter contains additional configuration options
  /// for the model, such as the system prompt and output type.
  @override
  Model createModel(ModelSettings settings) => OpenAiModel(
    modelName: modelName,
    embeddingModelName: embeddingModelName,
    apiKey: apiKey,
    outputSchema: settings.outputSchema,
    systemPrompt: settings.systemPrompt,
    tools: settings.tools,
    baseUrl: baseUrl,
    temperature: temperature,
    caps: caps,
  );

  @override
  final Set<ProviderCaps> caps;

  @override
  Future<Iterable<ModelInfo>> listModels() async {
    final client = oai.OpenAIClient(
      apiKey: apiKey,
      baseUrl: baseUrl?.toString(),
    );
    try {
      final res = await client.listModels();
      return res.data.map<ModelInfo>((m) {
        final id = m.id;

        final kind = () {
          if (id.contains('embedding')) return ModelKind.embedding;
          if (id.startsWith('dall-e') || id.contains('gpt-image')) {
            return ModelKind.image;
          }
          if (id.startsWith('whisper')) return ModelKind.audio;
          if (id.startsWith('tts-')) return ModelKind.tts;
          return ModelKind.chat; // default assumption
        }();

        return ModelInfo(name: id, providerName: name, kinds: {kind});
      }).toList();
    } finally {
      client.endSession();
    }
  }
}
