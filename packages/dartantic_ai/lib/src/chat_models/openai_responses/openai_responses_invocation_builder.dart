import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:openai_core/openai_core.dart' as openai;

import 'openai_responses_chat_options.dart';
import 'openai_responses_message_mapper.dart';
import 'openai_responses_options_mapper.dart';
import 'openai_responses_server_side_tools.dart';

/// Represents a fully-constructed OpenAI Responses API invocation.
///
/// Contains all parameters needed to execute a request, including mapped
/// history, request parameters, and server-side tool configuration.
class OpenAIResponsesInvocation {
  /// Creates a new invocation.
  const OpenAIResponsesInvocation({
    required this.store,
    required this.history,
    required this.parameters,
    required this.serverSide,
  });

  /// Whether session state should be persisted by the server.
  final bool store;

  /// Mapped conversation history ready for the API.
  final OpenAIResponsesHistorySegment history;

  /// Request-level parameters (temperature, tokens, etc.).
  final OpenAIRequestParameters parameters;

  /// Server-side tool configuration.
  final OpenAIServerSideToolContext serverSide;
}

/// Request-level parameters for the OpenAI Responses API.
///
/// Contains all model configuration and formatting options that apply to
/// the request as a whole.
class OpenAIRequestParameters {
  /// Creates a new request parameters object.
  const OpenAIRequestParameters({
    required this.temperature,
    required this.topP,
    required this.maxOutputTokens,
    required this.parallelToolCalls,
    required this.include,
    required this.metadata,
    required this.reasoning,
    required this.truncation,
    required this.textFormat,
    required this.user,
  });

  /// Sampling temperature.
  final double? temperature;

  /// Nucleus sampling parameter.
  final double? topP;

  /// Maximum number of output tokens.
  final int? maxOutputTokens;

  /// Whether the model may call multiple tools in parallel.
  final bool? parallelToolCalls;

  /// Specific response fields to include.
  final List<String>? include;

  /// Additional metadata forwarded to the API.
  final Map<String, dynamic>? metadata;

  /// Reasoning configuration for thinking models.
  final openai.ReasoningOptions? reasoning;

  /// Truncation configuration.
  final openai.Truncation? truncation;

  /// Text formatting/schema configuration.
  final openai.TextFormat? textFormat;

  /// End-user identifier for abuse monitoring.
  final String? user;
}

/// Server-side tool configuration context.
///
/// Specifies which server-side tools are enabled and their configuration.
class OpenAIServerSideToolContext {
  /// Creates a new server-side tool context.
  const OpenAIServerSideToolContext({
    required this.enabledTools,
    this.fileSearchConfig,
    this.webSearchConfig,
    this.codeInterpreterConfig,
    this.imageGenerationConfig,
  });

  /// Set of enabled server-side tools.
  final Set<OpenAIServerSideTool> enabledTools;

  /// Configuration for file_search tool.
  final FileSearchConfig? fileSearchConfig;

  /// Configuration for web_search tool.
  final WebSearchConfig? webSearchConfig;

  /// Configuration for code_interpreter tool.
  final CodeInterpreterConfig? codeInterpreterConfig;

  /// Configuration for image_generation tool.
  final ImageGenerationConfig? imageGenerationConfig;
}

/// Builds OpenAI Responses API invocations from Dartantic messages and options.
///
/// Responsible for:
/// - Merging runtime options with defaults
/// - Converting options to OpenAI-specific types
/// - Mapping conversation history
/// - Resolving server-side tool configuration
class OpenAIResponsesInvocationBuilder {
  /// Creates a new invocation builder.
  OpenAIResponsesInvocationBuilder({
    required this.messages,
    required this.options,
    required this.defaultOptions,
    required this.outputSchema,
  });

  /// Messages to be sent in this request.
  final List<ChatMessage> messages;

  /// Runtime options (may be null).
  final OpenAIResponsesChatModelOptions? options;

  /// Default options from model configuration.
  final OpenAIResponsesChatModelOptions defaultOptions;

  /// Optional output schema for typed responses.
  final JsonSchema? outputSchema;

  /// Builds the complete invocation.
  ///
  /// Throws [ArgumentError] if no new input is provided and no session exists.
  OpenAIResponsesInvocation build() {
    final store = options?.store ?? defaultOptions.store ?? true;
    final history = OpenAIResponsesMessageMapper.mapHistory(
      messages,
      store: store,
      imageDetail:
          options?.imageDetail ??
          defaultOptions.imageDetail ??
          openai.ImageDetail.auto,
    );

    if (!history.hasInput && history.previousResponseId == null) {
      throw ArgumentError('No new input provided to OpenAI Responses request');
    }

    final requestParameters = OpenAIRequestParameters(
      temperature: options?.temperature ?? defaultOptions.temperature,
      topP: options?.topP ?? defaultOptions.topP,
      maxOutputTokens:
          options?.maxOutputTokens ?? defaultOptions.maxOutputTokens,
      parallelToolCalls:
          options?.parallelToolCalls ?? defaultOptions.parallelToolCalls,
      include: options?.include ?? defaultOptions.include,
      metadata: OpenAIResponsesOptionsMapper.mergeMetadata(
        defaultOptions.metadata,
        options?.metadata,
      ),
      reasoning: OpenAIResponsesOptionsMapper.toReasoningOptions(
        raw: options?.reasoning ?? defaultOptions.reasoning,
        effort: options?.reasoningEffort ?? defaultOptions.reasoningEffort,
        summary: options?.reasoningSummary ?? defaultOptions.reasoningSummary,
      ),
      truncation: OpenAIResponsesOptionsMapper.toTruncation(
        options?.truncationStrategy ?? defaultOptions.truncationStrategy,
      ),
      textFormat: OpenAIResponsesOptionsMapper.resolveTextFormat(
        outputSchema,
        options?.responseFormat ?? defaultOptions.responseFormat,
      ),
      user: options?.user ?? defaultOptions.user,
    );

    final serverSide = OpenAIServerSideToolContext(
      enabledTools: _resolveServerSideTools(),
      fileSearchConfig:
          options?.fileSearchConfig ?? defaultOptions.fileSearchConfig,
      webSearchConfig:
          options?.webSearchConfig ?? defaultOptions.webSearchConfig,
      codeInterpreterConfig:
          options?.codeInterpreterConfig ??
          defaultOptions.codeInterpreterConfig,
      imageGenerationConfig:
          options?.imageGenerationConfig ??
          defaultOptions.imageGenerationConfig,
    );

    return OpenAIResponsesInvocation(
      store: store,
      history: history,
      parameters: requestParameters,
      serverSide: serverSide,
    );
  }

  Set<OpenAIServerSideTool> _resolveServerSideTools() {
    final requested = options?.serverSideTools;
    if (requested != null) {
      return {...requested};
    }
    final defaults = defaultOptions.serverSideTools;
    if (defaults != null) {
      return {...defaults};
    }
    return <OpenAIServerSideTool>{};
  }
}
