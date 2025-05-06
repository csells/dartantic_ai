import '../../models/implementations/openai_model.dart';
import '../../models/interface/model.dart';
import '../../models/interface/model_settings.dart';
import '../../platform/platform.dart' as platform;
import '../interface/provider.dart';

/// Provider for OpenAI models.
///
/// This provider creates instances of [OpenAiModel] using the specified
/// model name and API key.
class OpenAiProvider extends Provider {
  /// Creates a new [OpenAiProvider] with the given parameters.
  ///
  /// The [modelName] is the name of the OpenAI model to use.
  /// If not provided, [defaultModelName] is used.
  /// The [apiKey] is the API key to use for authentication.
  /// If not provided, it's retrieved from the environment.
  OpenAiProvider({String? modelName, String? apiKey})
    : modelName = modelName ?? defaultModelName,
      apiKey = apiKey ?? platform.getEnv(apiKeyName);

  /// The default model name to use if none is provided.
  static const defaultModelName = 'gpt-4o';

  /// The name of the environment variable that contains the API key.
  static const apiKeyName = 'OPENAI_API_KEY';

  /// The display name for this provider, in the format "openai:modelName".
  @override
  String get displayName => 'openai:$modelName';

  /// The name of the OpenAI model to use.
  final String modelName;

  /// The API key to use for authentication with the OpenAI API.
  final String apiKey;

  /// Creates a [Model] instance using this provider's configuration.
  ///
  /// The [settings] parameter contains additional configuration options
  /// for the model, such as the system prompt and output type.
  @override
  Model createModel(ModelSettings settings) => OpenAiModel(
    modelName: modelName,
    apiKey: apiKey,
    outputType: settings.outputType,
    systemPrompt: settings.systemPrompt,
    tools: settings.tools,
  );
}
