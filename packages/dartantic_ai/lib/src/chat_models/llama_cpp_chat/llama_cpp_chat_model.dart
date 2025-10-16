import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:logging/logging.dart';

import 'llama_cpp_chat_options.dart';
import 'llama_cpp_message_mappers.dart' as llama_cpp_mappers;

export 'llama_cpp_chat_options.dart';

/// Wrapper around llama.cpp that enables interaction with local LLMs.
///
/// This implementation uses the llama_cpp_dart package to run models locally.
/// Models must be in GGUF format and specified by file path.
class LlamaCppChatModel extends ChatModel<LlamaCppChatOptions> {
  /// Creates a [LlamaCppChatModel] instance.
  ///
  /// The [name] parameter should be the path to a GGUF model file.
  LlamaCppChatModel({
    required String name,
    List<Tool>? tools,
    super.temperature,
    LlamaCppChatOptions? defaultOptions,
    String? libraryPath,
    ModelParams? modelParams,
    ContextParams? contextParams,
    SamplerParams? samplerParams,
    PromptFormat? promptFormat,
  }) : _modelPath = name,
       _libraryPath = libraryPath,
       _modelParams = modelParams,
       _contextParams = contextParams,
       _samplerParams = samplerParams,
       _promptFormat = promptFormat ?? ChatMLFormat(),
       super(
         name: name,
         defaultOptions: defaultOptions ?? const LlamaCppChatOptions(),
         tools: tools,
       ) {
    _logger.info(
      'Creating LlamaCpp model from path: $name '
      'with ${tools?.length ?? 0} tools, temp: $temperature',
    );

    if (tools != null && tools.isNotEmpty) {
      _logger.warning(
        'LlamaCpp does not natively support tool calling. '
        'Tools will be ignored.',
      );
    }
  }

  static final Logger _logger = Logger('dartantic.chat.models.llama_cpp');

  final String _modelPath;
  final String? _libraryPath;
  final ModelParams? _modelParams;
  final ContextParams? _contextParams;
  final SamplerParams? _samplerParams;
  final PromptFormat _promptFormat;

  LlamaParent? _llamaParent;
  bool _isInitialized = false;

  /// Initializes the model by loading it into memory.
  Future<void> _initialize() async {
    if (_isInitialized) return;

    _logger.info('Initializing LlamaCpp model from: $_modelPath');

    if (_libraryPath != null) {
      Llama.libraryPath = _libraryPath!;
    }

    final loadCommand = LlamaLoad(
      path: _modelPath,
      modelParams: _modelParams ?? ModelParams(),
      contextParams: _contextParams ?? ContextParams(),
      samplingParams: _samplerParams ?? SamplerParams(),
      format: _promptFormat,
    );

    _llamaParent = LlamaParent(loadCommand);

    try {
      await _llamaParent!.init();
    } catch (e) {
      _logger.warning('Init timeout (expected for large models): $e');
      // Continue - the model may still be loading
    }

    // Wait for model to be ready (can take longer than init timeout)
    _logger.info('Waiting for model to be ready...');
    const maxAttempts = 120; // 2 minutes total
    var attempts = 0;

    while (_llamaParent!.status != LlamaStatus.ready && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 1000));
      attempts++;

      if (attempts % 10 == 0) {
        _logger.info(
          'Still waiting for model... Status: ${_llamaParent!.status} '
          '($attempts seconds elapsed)',
        );
      }

      if (_llamaParent!.status == LlamaStatus.error) {
        throw StateError('Error loading LlamaCpp model');
      }
    }

    if (_llamaParent!.status != LlamaStatus.ready) {
      _logger.warning(
        'Model status is ${_llamaParent!.status} after $attempts seconds. '
        'Attempting to continue anyway.',
      );
    }

    _isInitialized = true;
    _logger.info('LlamaCpp model initialized successfully');
  }

  @override
  Stream<ChatResult<ChatMessage>> sendStream(
    List<ChatMessage> messages, {
    LlamaCppChatOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    if (outputSchema != null) {
      throw ArgumentError(
        'LlamaCpp does not support typed output (outputSchema). '
        'Use outputSchema without LlamaCpp provider.',
      );
    }

    // Initialize if needed
    await _initialize();

    if (_llamaParent == null) {
      throw StateError('LlamaCpp model not initialized');
    }

    _logger.info(
      'Starting LlamaCpp chat stream with ${messages.length} messages',
    );

    // Convert messages to prompt
    final prompt = messages.toPrompt();
    _logger.fine('Prompt: $prompt');

    // Send prompt to model
    await _llamaParent!.sendPrompt(prompt);

    // Buffer to accumulate complete response text
    final responseBuffer = StringBuffer();
    var chunkCount = 0;

    // Listen to the stream and yield results
    await for (final chunk in _llamaParent!.stream) {
      chunkCount++;
      _logger.fine('Received LlamaCpp stream chunk $chunkCount: "$chunk"');

      // Accumulate response
      responseBuffer.write(chunk);

      // Check if this is the final chunk (empty string signals completion)
      final isDone = chunk.isEmpty;

      if (!isDone) {
        // Yield intermediate result with accumulated text
        final result = llama_cpp_mappers.ChatResultMapper(
          responseBuffer.toString(),
          isDone: false,
        ).toChatResult();

        yield ChatResult<ChatMessage>(
          output: result.output,
          messages: result.messages,
          finishReason: result.finishReason,
          metadata: result.metadata,
        );
      } else {
        // Yield final result
        final result = llama_cpp_mappers.ChatResultMapper(
          responseBuffer.toString(),
          isDone: true,
        ).toChatResult();

        yield ChatResult<ChatMessage>(
          output: result.output,
          messages: result.messages,
          finishReason: result.finishReason,
          metadata: result.metadata,
        );

        _logger.info('LlamaCpp stream completed with $chunkCount chunks');
        break;
      }
    }
  }

  @override
  void dispose() {
    unawaited(_llamaParent?.dispose());
    _isInitialized = false;
    _llamaParent = null;
    _logger.info('LlamaCpp model disposed');
  }
}
