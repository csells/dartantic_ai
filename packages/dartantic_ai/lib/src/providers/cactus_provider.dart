import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

import '../chat_models/cactus_chat/cactus_chat_model.dart';
import '../chat_models/cactus_chat/cactus_chat_options.dart';

/// Provider for Cactus framework.
class CactusProvider
    extends Provider<CactusChatOptions, EmbeddingsModelOptions> {
  /// Creates a new Cactus provider instance.
  CactusProvider(
    this._model, {
    String? name,
    String? displayName,
    Map<ModelKind, String>? defaultModelNames,
  })
    : super(
         name: name ?? 'cactus',
         displayName: displayName ?? 'Cactus',
         defaultModelNames:
             defaultModelNames ?? {
          ModelKind.chat: 'cactus-framework',
        },
        baseUrl: null,
        apiKey: null,
        apiKeyName: null,
        caps: {
          ProviderCaps.chat,
          ProviderCaps.multiToolCalls,
          ProviderCaps.typedOutput,
          ProviderCaps.vision,
        },
      );

  final CactusChatModel _model;
  static final Logger _logger = Logger('dartantic.chat.providers.cactus');

  @override
  ChatModel<CactusChatOptions> createChatModel({
    String? name,
    /// Not used for the cactus provider
    List<Tool>? tools,
    double? temperature,
    CactusChatOptions? options,
  }) {
    final modelName = name ?? defaultModelNames[ModelKind.chat]!;
    _logger.info(
      'Creating Cactus model: $modelName with ${tools?.length ?? 0} tools, '
      'temp: $temperature',
    );

    return CactusChatModel(
      name: modelName,
      temperature: temperature ?? _model.temperature,
      defaultOptions: CactusChatOptions(
        maxTokens: options?.maxTokens,
      ),
      sendChatStream: _model.sendChatStream,
    );
  }

  @override
  EmbeddingsModel<EmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    EmbeddingsModelOptions? options,
  }) => throw UnimplementedError();

  @override
  Stream<ModelInfo> listModels() async* {
    throw UnimplementedError();
  }
}
