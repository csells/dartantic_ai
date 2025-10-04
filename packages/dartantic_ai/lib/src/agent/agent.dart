import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../logging_options.dart';
import '../providers/providers.dart';
import 'model_string_parser.dart';
import 'orchestrators/default_streaming_orchestrator.dart';
import 'orchestrators/streaming_orchestrator.dart';
import 'orchestrators/typed_output_streaming_orchestrator.dart';
import 'streaming_state.dart';
import 'tool_constants.dart';

/// An agent that manages chat models and provides tool execution and message
/// collection capabilities.
///
/// The Agent handles:
/// - Provider and model creation from string specification
/// - Tool call ID assignment for providers that don't provide them
/// - Automatic tool execution with error handling
/// - Message collection and streaming UX enhancement
/// - Model caching and lifecycle management
class Agent {
  /// Creates an agent with the specified model.
  ///
  /// The [model] parameter should be in the format "providerName",
  /// "providerName:modelName", or "providerName/modelName". For example:
  /// "openai", "openai:gpt-4o", "openai/gpt-4o", "anthropic",
  /// "anthropic:claude-3-sonnet", etc.
  ///
  /// Optional parameters:
  /// - [tools]: List of tools the agent can use
  /// - [temperature]: Model temperature (0.0 to 1.0)
  Agent(
    String model, {
    List<Tool>? tools,
    double? temperature,
    String? displayName,
    this.chatModelOptions,
    this.embeddingsModelOptions,
  }) {
    // parse the model string into a provider name, chat model name, and
    // embeddings model name
    final parser = ModelStringParser.parse(model);
    final providerName = parser.providerName;
    final chatModelName = parser.chatModelName;
    final embeddingsModelName = parser.embeddingsModelName;

    _logger.info(
      'Creating agent with model: $model (provider: $providerName, '
      'chat model: $chatModelName, '
      'embeddings model: $embeddingsModelName)',
    );

    // cache the provider name from the input; it could be an alias
    _providerName = providerName;
    _displayName = displayName;

    // Store provider and model parameters
    _provider = Providers.get(providerName);

    _chatModelName = chatModelName;
    _embeddingsModelName = embeddingsModelName;

    _tools = tools;
    _temperature = temperature;

    _logger.fine(
      'Agent created successfully with ${tools?.length ?? 0} tools, '
      'temperature: $temperature',
    );
  }

  /// Creates an agent from a provider
  Agent.forProvider(
    Provider provider, {
    String? chatModelName,
    String? embeddingsModelName,
    List<Tool>? tools,
    double? temperature,
    String? displayName,
    this.chatModelOptions,
    this.embeddingsModelOptions,
  }) {
    _logger.info(
      'Creating agent from provider: ${provider.name}, '
      'chat model: $chatModelName, '
      'embeddings model: $embeddingsModelName',
    );

    _providerName = provider.name;
    _displayName = displayName;

    // Store provider and model parameters
    _provider = provider;

    _chatModelName = chatModelName;
    _embeddingsModelName = embeddingsModelName;

    _tools = tools;
    _temperature = temperature;

    _logger.fine(
      'Agent created from provider with ${tools?.length ?? 0} tools, '
      'temperature: $temperature',
    );
  }

  /// Gets the provider name.
  String get providerName => _providerName;

  /// Gets the chat model name.
  String? get chatModelName => _chatModelName;

  /// Gets the embeddings model name.
  String? get embeddingsModelName => _embeddingsModelName;

  /// Gets the fully qualified model name.
  String get model => ModelStringParser(
    providerName,
    chatModelName:
        chatModelName ??
        (_provider.defaultModelNames.containsKey(ModelKind.chat)
            ? _provider.defaultModelNames[ModelKind.chat]
            : null),
    embeddingsModelName: embeddingsModelName,
  ).toString();

  /// Gets the display name.
  String get displayName => _displayName ?? _provider.displayName;

  /// Gets the chat model options.
  final ChatModelOptions? chatModelOptions;

  /// Gets the embeddings model options.
  final EmbeddingsModelOptions? embeddingsModelOptions;

  late final String _providerName;
  late final Provider _provider;
  late final String? _chatModelName;
  late final String? _embeddingsModelName;
  late final List<Tool>? _tools;
  late final double? _temperature;
  late final String? _displayName;

  static final Logger _logger = Logger('dartantic.chat_agent');

  /// Invokes the agent with the given prompt and returns the final result.
  ///
  /// This method internally uses [sendStream] and accumulates all results.
  Future<ChatResult<String>> send(
    String prompt, {
    List<ChatMessage> history = const [],
    List<Part> attachments = const [],
    JsonSchema? outputSchema,
  }) async {
    _logger.info(
      'Running agent with prompt and ${history.length} history messages',
    );

    final allNewMessages = <ChatMessage>[];
    var finalOutput = '';
    var finalResult = ChatResult<String>(
      output: '',
      finishReason: FinishReason.unspecified,
      metadata: const <String, dynamic>{},
      usage: const LanguageModelUsage(),
    );

    // Accumulate metadata from all streaming chunks
    final accumulatedMetadata = <String, dynamic>{};
    final thinkingBuffer = StringBuffer();

    await for (final result in sendStream(
      prompt,
      history: history,
      attachments: attachments,
      outputSchema: outputSchema,
    )) {
      if (result.output.isNotEmpty) {
        finalOutput += result.output;
      }
      allNewMessages.addAll(result.messages);
      finalResult = result;

      // Accumulate thinking from streaming chunks
      final thinking = result.metadata['thinking'] as String?;
      if (thinking != null && thinking.isNotEmpty) {
        thinkingBuffer.write(thinking);
      }

      // Merge other metadata (preserving response-level info from final chunk)
      for (final entry in result.metadata.entries) {
        if (entry.key != 'thinking') {
          accumulatedMetadata[entry.key] = entry.value;
        }
      }
    }

    // Build final metadata with accumulated thinking
    final mergedMetadata = <String, dynamic>{
      ...accumulatedMetadata,
      if (thinkingBuffer.isNotEmpty) 'thinking': thinkingBuffer.toString(),
    };

    // Return final result with all accumulated messages
    finalResult = ChatResult<String>(
      id: finalResult.id,
      output: finalOutput,
      messages: allNewMessages,
      finishReason: finalResult.finishReason,
      metadata: mergedMetadata,
      usage: finalResult.usage,
    );

    _logger.info(
      'Agent run completed with ${allNewMessages.length} new messages, '
      'finish reason: ${finalResult.finishReason}',
    );

    return finalResult;
  }

  /// Sends the given [prompt] and [attachments] to the agent and returns a
  /// typed response.
  ///
  /// Returns an [ChatResult<TOutput>] containing the output converted to type
  /// [TOutput]. Uses [outputFromJson] to convert the JSON response if provided,
  /// otherwise returns the decoded JSON.
  Future<ChatResult<TOutput>> sendFor<TOutput extends Object>(
    String prompt, {
    required JsonSchema outputSchema,
    dynamic Function(Map<String, dynamic> json)? outputFromJson,
    List<ChatMessage> history = const [],
    List<Part> attachments = const [],
  }) async {
    final response = await send(
      prompt,
      outputSchema: outputSchema,
      history: history,
      attachments: attachments,
    );

    // Since runStream now normalizes output, JSON is always in response.output
    final jsonString = response.output;
    if (jsonString.isEmpty) {
      throw const FormatException(
        'No JSON output found in response. Expected JSON in response.output.',
      );
    }

    final outputJson = jsonDecode(jsonString);
    final typedOutput = outputFromJson?.call(outputJson) ?? outputJson;
    return ChatResult<TOutput>(
      id: response.id,
      output: typedOutput,
      messages: response.messages,
      finishReason: response.finishReason,
      metadata: response.metadata,
      usage: response.usage,
    );
  }

  /// Streams responses from the agent, handling tool execution automatically.
  ///
  /// Returns a stream of [ChatResult] where:
  /// - [ChatResult.output] contains streaming text chunks
  /// - [ChatResult.messages] contains new messages since the last result
  Stream<ChatResult<String>> sendStream(
    String prompt, {
    List<ChatMessage> history = const [],
    List<Part> attachments = const [],
    JsonSchema? outputSchema,
  }) async* {
    _logger.info(
      'Starting agent stream with prompt and ${history.length} '
      'history messages',
    );

    // Prepare tools, including return_result if needed
    var tools = _tools;
    if (outputSchema != null) {
      final returnResultTool = Tool<Map<String, dynamic>>(
        name: kReturnResultToolName,
        description:
            'REQUIRED: You MUST call this tool to return the final result. '
            'Use this tool to format and return your response according to '
            'the specified JSON schema. Call this after gathering any '
            'necessary information from other tools.',
        inputSchema: outputSchema,

        onCall: (args) async => json.encode(args),
      );
      tools = [...?_tools, returnResultTool];
    }

    // Create model directly from provider
    final model = _provider.createChatModel(
      name: _chatModelName,
      tools: tools,
      temperature: _temperature,
      options: chatModelOptions,
    );

    try {
      // Create user message
      final newUserMessage = ChatMessage.user(prompt, parts: attachments);
      _assertNoMultipleTextParts([newUserMessage]);

      // Initialize state BEFORE yielding to prevent race conditions
      final conversationHistory = List<ChatMessage>.from([
        ...history,
        newUserMessage,
      ]);

      // Now yield the user message
      yield ChatResult<String>(
        id: '',
        output: '',
        messages: [newUserMessage],
        finishReason: FinishReason.unspecified,
        metadata: const <String, dynamic>{},
        usage: const LanguageModelUsage(),
      );

      final state = StreamingState(
        conversationHistory: conversationHistory,
        toolMap: {for (final tool in model.tools ?? <Tool>[]) tool.name: tool},
      );

      // Select and configure orchestrator
      // Use the model's actual tools list (after any filtering by the model)
      final orchestrator = _selectOrchestrator(
        outputSchema: outputSchema,
        tools: model.tools, // This is the filtered list from the model
      );

      orchestrator.initialize(state);

      try {
        // Main streaming loop
        while (!state.done) {
          await for (final result in orchestrator.processIteration(
            model,
            state,
            outputSchema: outputSchema,
          )) {
            // Yield streaming text or metadata
            if (result.output.isNotEmpty || result.metadata.isNotEmpty) {
              yield ChatResult<String>(
                id: state.lastResult.id.isEmpty ? '' : state.lastResult.id,
                output: result.output,
                messages: const [],
                finishReason: result.finishReason,
                metadata: result.metadata,
                usage: result.usage ?? const LanguageModelUsage(),
              );
            }

            // Yield messages
            if (result.messages.isNotEmpty) {
              for (final message in result.messages) {
                _assertNoMultipleTextParts([message]);
              }
              yield ChatResult<String>(
                id: state.lastResult.id.isEmpty ? '' : state.lastResult.id,
                output: '',
                messages: result.messages,
                finishReason: result.finishReason,
                metadata: result.metadata,
                usage: result.usage ?? const LanguageModelUsage(),
              );
            }

            // Check continuation
            if (!result.shouldContinue) {
              state.complete();
            }
          }
        }
      } finally {
        orchestrator.finalize(state);
      }
    } finally {
      model.dispose();
    }
  }

  /// Embed query text and return result with usage data.
  Future<EmbeddingsResult> embedQuery(String query) => _provider
      .createEmbeddingsModel(
        name: _embeddingsModelName,
        options: embeddingsModelOptions,
      )
      .embedQuery(query);

  /// Embed texts and return results with usage data.
  Future<BatchEmbeddingsResult> embedDocuments(List<String> texts) => _provider
      .createEmbeddingsModel(
        name: _embeddingsModelName,
        options: embeddingsModelOptions,
      )
      .embedDocuments(texts);

  /// Selects the appropriate orchestrator based on context
  StreamingOrchestrator _selectOrchestrator({
    required JsonSchema? outputSchema,
    required List<Tool>? tools,
  }) {
    if (outputSchema != null) {
      final hasReturnResultTool =
          tools?.any((t) => t.name == kReturnResultToolName) ?? false;

      return TypedOutputStreamingOrchestrator(
        hasReturnResultTool: hasReturnResultTool,
      );
    }

    return const DefaultStreamingOrchestrator();
  }

  /// Asserts that no message in the list contains more than one TextPart.
  ///
  /// This helps catch streaming consolidation issues where text content gets
  /// split into multiple TextPart objects instead of being properly accumulated
  /// into a single TextPart.
  ///
  /// Throws an AssertionError in debug mode if any message violates this rule.
  void _assertNoMultipleTextParts(List<ChatMessage> messages) {
    assert(() {
      for (final message in messages) {
        final textParts = message.parts.whereType<TextPart>().toList();
        if (textParts.length > 1) {
          throw AssertionError(
            'Message contains ${textParts.length} TextParts but should have '
            'at most 1. Message: $message. '
            'TextParts: ${textParts.map((p) => '"${p.text}"').join(', ')}. '
            'This indicates a streaming consolidation bug.',
          );
        }
      }
      return true;
    }());
  }

  /// Gets an environment map for the agent.
  static Map<String, String> environment = {};

  /// Controls whether environment lookups should only use [Agent.environment]
  /// and ignore [Platform.environment]. This is useful for testing to ensure
  /// complete control over environment variables.
  static bool useAgentEnvironmentOnly = false;

  /// Global logging configuration for all Agent operations.
  ///
  /// Controls logging level, filtering, and output handling for all dartantic
  /// loggers. Setting this property automatically configures the logging system
  /// with the specified options.
  ///
  /// Example usage:
  /// ```dart
  /// // Filter to only OpenAI operations
  /// Agent.loggingOptions = LoggingOptions(filter: 'openai');
  ///
  /// // Custom level and handler
  /// Agent.loggingOptions = LoggingOptions(
  ///   level: Level.FINE,
  ///   onRecord: (record) => myLogger.log(record),
  /// );
  /// ```
  static LoggingOptions get loggingOptions => _loggingOptions;
  static LoggingOptions _loggingOptions = const LoggingOptions();
  static StreamSubscription<LogRecord>? _loggingSubscription;

  /// Sets the global logging configuration and applies it immediately.
  static set loggingOptions(LoggingOptions options) {
    _loggingOptions = options;
    _setupLogging();
  }

  /// Sets up the logging system with the current options.
  static void _setupLogging() {
    // Cancel existing subscription if any
    unawaited(_loggingSubscription?.cancel());

    // Configure root logger level
    Logger.root.level = _loggingOptions.level;

    // Set up new subscription with filtering
    _loggingSubscription = Logger.root.onRecord.listen((record) {
      // Apply level filter (should already be handled by Logger.root.level)
      if (record.level < _loggingOptions.level) return;

      // Apply name filter - empty string matches all
      if (_loggingOptions.filter.isNotEmpty &&
          !record.loggerName.contains(_loggingOptions.filter)) {
        return;
      }

      // Call the configured handler
      _loggingOptions.onRecord(record);
    });
  }
}
