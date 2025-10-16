import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:logging/logging.dart';

import '../chat_models/llama_cpp_chat/llama_cpp_chat_model.dart';

/// Provider for local llama.cpp models (GGUF format).
///
/// This provider uses the llama_cpp_dart package to run models locally.
/// Unlike cloud-based providers, this requires:
/// 1. A GGUF format model file on the local filesystem
/// 2. The llama.cpp shared library to be available
///
/// The model name should be the full path to the GGUF model file.
class LlamaCppProvider
    extends Provider<LlamaCppChatOptions, EmbeddingsModelOptions> {
  /// Creates a new LlamaCpp provider instance.
  ///
  /// The [modelPath] is the full path to a GGUF model file.
  /// The [libraryPath] is the optional path to the llama.cpp shared library.
  LlamaCppProvider({
    super.name = 'llama_cpp',
    super.displayName = 'LlamaCpp',
    String? modelPath,
    this.libraryPath,
    this.modelParams,
    this.contextParams,
    this.samplerParams,
    this.promptFormat,
    super.apiKey,
    super.baseUrl,
    super.apiKeyName,
  }) : super(
         defaultModelNames: {ModelKind.chat: modelPath ?? ''},
         caps: const {ProviderCaps.chat},
       );

  static final Logger _logger = Logger('dartantic.chat.providers.llama_cpp');

  /// Path to the llama.cpp shared library.
  final String? libraryPath;

  /// Model parameters for loading the model.
  final ModelParams? modelParams;

  /// Context parameters for the model.
  final ContextParams? contextParams;

  /// Sampler parameters for text generation.
  final SamplerParams? samplerParams;

  /// Prompt format to use (e.g., ChatMLFormat, Llama2ChatFormat).
  final PromptFormat? promptFormat;

  @override
  ChatModel<LlamaCppChatOptions> createChatModel({
    String? name,
    List<Tool>? tools,
    double? temperature,
    LlamaCppChatOptions? options,
  }) {
    final modelPath = name ?? defaultModelNames[ModelKind.chat];
    if (modelPath == null || modelPath.isEmpty) {
      throw ArgumentError(
        'LlamaCpp provider requires a model path. '
        'Provide a path to a GGUF model file.',
      );
    }

    _logger.info(
      'Creating LlamaCpp model from: $modelPath with ${tools?.length ?? 0} '
      'tools, temp: $temperature',
    );

    return LlamaCppChatModel(
      name: modelPath,
      tools: tools,
      temperature: temperature,
      defaultOptions: options ?? const LlamaCppChatOptions(),
      libraryPath: libraryPath,
      modelParams: modelParams,
      contextParams: contextParams,
      samplerParams: samplerParams,
      promptFormat: promptFormat,
    );
  }

  @override
  EmbeddingsModel<EmbeddingsModelOptions> createEmbeddingsModel({
    String? name,
    EmbeddingsModelOptions? options,
  }) {
    throw UnsupportedError(
      'LlamaCpp does not support embeddings models in this implementation',
    );
  }

  @override
  Stream<ModelInfo> listModels() async* {
    // LlamaCpp uses local model files, so there's no API to list models.
    // We could potentially scan a directory, but that's beyond the scope
    // of this basic implementation.
    _logger.info('LlamaCpp provider does not support listing models');
  }
}
