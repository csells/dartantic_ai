import 'package:meta/meta.dart';

/// OpenAI-provided server-side tools that can be enabled for a Responses call.
enum OpenAIServerSideTool {
  /// Web search (sometimes surfaced as `web_search_preview`).
  webSearch('web_search'),

  /// File search across uploaded documents / vector stores.
  fileSearch('file_search'),

  /// Remote computer use / browser control.
  computerUse('computer_use'),

  /// Image generation (text-to-image) capability.
  imageGeneration('image_generation'),

  /// Code interpreter (Python sandbox with optional container reuse).
  codeInterpreter('code_interpreter');

  const OpenAIServerSideTool(this.apiName);

  /// Canonical identifier expected by the OpenAI Responses API.
  final String apiName;
}

/// Configuration for the OpenAI Responses `file_search` tool.
@immutable
class FileSearchConfig {
  /// Creates a new file search configuration.
  const FileSearchConfig({
    this.vectorStoreIds = const <String>[],
    this.maxResults,
    this.filters,
    this.ranker,
    this.scoreThreshold,
  });

  /// Explicit vector store IDs that should be searched.
  final List<String> vectorStoreIds;

  /// Limits how many matches the server should return.
  final int? maxResults;

  /// Optional metadata filters applied server-side.
  final Map<String, dynamic>? filters;

  /// Ranking configuration identifier (provider-specific).
  final String? ranker;

  /// Score threshold for returned results (0–1 range).
  final num? scoreThreshold;

  /// Whether at least one vector store identifier has been supplied.
  bool get hasVectorStores => vectorStoreIds.isNotEmpty;
}

/// Controls how much context is gathered during server-side web search.
enum WebSearchContextSize {
  /// Lightweight search context.
  low,

  /// Balanced context size (default behaviour).
  medium,

  /// Maximum amount of available context.
  high,

  /// Custom context configuration (provider interprets value).
  other,
}

/// Approximate geographic hints for web search personalisation.
@immutable
class WebSearchLocation {
  /// Creates a new web search user location hint.
  const WebSearchLocation({
    this.city,
    this.region,
    this.country,
    this.timezone,
  });

  /// City hint (human-readable, e.g. "San Francisco").
  final String? city;

  /// Region or state (e.g. "CA").
  final String? region;

  /// Country code or full name.
  final String? country;

  /// IANA timezone identifier.
  final String? timezone;

  /// Returns true when no fields are populated.
  bool get isEmpty =>
      city == null && region == null && country == null && timezone == null;
}

/// Configuration for the OpenAI Responses `web_search` tool.
@immutable
class WebSearchConfig {
  /// Creates a new web search configuration.
  const WebSearchConfig({
    this.contextSize,
    this.location,
    this.followupQuestions,
  });

  /// Desired context size (falls back to provider defaults when omitted).
  final WebSearchContextSize? contextSize;

  /// Optional approximate user location for localized results.
  final WebSearchLocation? location;

  /// Whether the model should surface follow-up questions in metadata.
  final bool? followupQuestions;
}

/// Configuration for the OpenAI Responses `code_interpreter` tool.
@immutable
class CodeInterpreterConfig {
  /// Creates a new code interpreter configuration.
  const CodeInterpreterConfig({this.containerId, this.fileIds});

  /// Container identifier reused from a previous Responses turn.
  final String? containerId;

  /// File identifiers that should be mounted inside the container.
  final List<String>? fileIds;

  /// Returns true when a reusable container was requested explicitly.
  bool get shouldReuseContainer =>
      containerId != null && containerId!.trim().isNotEmpty;
}

/// Configuration for the OpenAI Responses `computer_use` tool.
@immutable
class ComputerUseConfig {
  /// Creates a new computer use configuration.
  const ComputerUseConfig({
    this.displayHeight = 720,
    this.displayWidth = 1280,
    this.environment = 'browser',
  });

  /// Reported viewport height in pixels.
  final int displayHeight;

  /// Reported viewport width in pixels.
  final int displayWidth;

  /// Target environment (e.g. `browser`, `desktop`).
  final String environment;
}
