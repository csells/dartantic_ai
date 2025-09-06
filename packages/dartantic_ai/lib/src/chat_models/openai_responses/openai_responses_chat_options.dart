import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:meta/meta.dart';

import 'openai_responses_built_in_tools.dart';
import 'openai_responses_cache_config.dart';

/// Generation options for the OpenAI Responses API chat model.
@immutable
class OpenAIResponsesChatOptions extends ChatModelOptions {
  /// Creates a new options instance for the Responses API.
  const OpenAIResponsesChatOptions({
    this.maxTokens,
    this.temperature,
    this.topP,
    this.stop,
    this.seed,
    this.responseFormat,
    this.parallelToolCalls,
    this.user,
    this.toolChoice,
    this.reasoningEffort,
    this.reasoningSummary,
    this.serverSideTools,
    this.fileSearchConfig,
    this.webSearchConfig,
    this.cacheConfig,
  });

  /// The maximum number of tokens to generate in the response.
  /// Some Responses API variants call this `max_output_tokens`.
  final int? maxTokens;

  /// Sampling temperature (0–2).
  final double? temperature;

  /// Nucleus sampling top-p.
  final double? topP;

  /// Stop sequences.
  final List<String>? stop;

  /// Best-effort deterministic sampling seed.
  final int? seed;

  /// Native typed output format descriptor (e.g., json_schema object map).
  final dynamic responseFormat;

  /// Whether to enable parallel tool calling.
  final bool? parallelToolCalls;

  /// End-user identifier for abuse monitoring.
  final String? user;

  /// Controls which tool is called by the model.
  final dynamic toolChoice;

  /// Preferred reasoning effort for models that support thinking/reasoning.
  final OpenAIReasoningEffort? reasoningEffort;

  /// Preferred reasoning summary exposure (where supported by Responses API).
  /// When set, providers may stream a reasoning summary channel.
  final OpenAIReasoningSummary? reasoningSummary;

  /// OpenAI Responses server-side tools to enable (e.g., webSearch,
  /// fileSearch).
  ///
  /// Provider-specific, akin to reasoning configuration. When supplied, these
  /// are mapped to native built-ins in the Responses API request.
  final Set<OpenAIServerSideTool>? serverSideTools;

  /// Optional configuration for file_search.
  final FileSearchConfig? fileSearchConfig;

  /// Optional configuration for web_search.
  final WebSearchConfig? webSearchConfig;

  /// Prompt caching configuration.
  final OpenAICacheConfig? cacheConfig;
}

/// Reasoning effort levels for OpenAI Responses models that support thinking.
enum OpenAIReasoningEffort {
  /// Low reasoning effort.
  low,

  /// Medium reasoning effort.
  medium,

  /// High reasoning effort.
  high,
}

/// Reasoning summary exposure preference for Responses API.
enum OpenAIReasoningSummary {
  /// Request a detailed reasoning summary.
  detailed,

  /// Request a concise reasoning summary.
  concise,

  /// Let the model decide (recommended default).
  auto,

  /// Do not request a summary (omit the summary field in payload).
  none,
}
