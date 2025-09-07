import 'package:meta/meta.dart';

/// Server-side tools exposed by the OpenAI Responses API.
/// These require no external implementation and can be enabled in the request.
enum OpenAIServerSideTool {
  /// Web search tool.
  webSearch('web_search'),

  /// File search tool.
  fileSearch('file_search'),

  /// Computer use tool.
  computerUse('computer_use'),

  /// Image generation tool.
  imageGeneration('image_generation'),

  /// Code interpreter tool.
  codeInterpreter('code_interpreter');

  const OpenAIServerSideTool(this.apiName);

  /// The API name of the server-side tool.
  final String apiName;
}

/// Configuration for the file search tool.
@immutable
class FileSearchConfig {
  /// Creates a new configuration instance for the file search tool.
  const FileSearchConfig({this.maxResults, this.metadataFilters});

  /// Maximum number of results to return.
  final int? maxResults;

  /// Optional metadata filters to apply to the document index.
  final Map<String, dynamic>? metadataFilters;

  /// Converts the configuration to a request JSON object.
  Map<String, dynamic> toRequestJson() => {
    if (maxResults != null) 'max_results': maxResults,
    if (metadataFilters != null) 'metadata_filters': metadataFilters,
  };
}

/// Configuration for the web search tool.
@immutable
class WebSearchConfig {
  /// Creates a new configuration instance for the web search tool.
  const WebSearchConfig({this.maxResults, this.siteFilter, this.timeRange});

  /// Maximum number of search results.
  final int? maxResults;

  /// Optional site/domain restriction (e.g., "site:openai.com").
  final String? siteFilter;

  /// Optional recency/time range (e.g., "past_week").
  final String? timeRange;

  /// Converts the configuration to a request JSON object.
  Map<String, dynamic> toRequestJson() => {
    if (maxResults != null) 'max_results': maxResults,
    if (siteFilter != null && siteFilter!.isNotEmpty) 'site_filter': siteFilter,
    if (timeRange != null && timeRange!.isNotEmpty) 'time_range': timeRange,
  };
}

// No container config; use OpenAIResponsesChatOptions.serverSideTools and
// per-tool configs on the options object (fileSearchConfig, webSearchConfig).
