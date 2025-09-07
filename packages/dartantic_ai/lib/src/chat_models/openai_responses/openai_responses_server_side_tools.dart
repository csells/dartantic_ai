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

  /// Code interpreter tool for executing Python code.
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

/// Configuration for the code interpreter tool.
@immutable
class CodeInterpreterConfig {
  /// Creates a new configuration instance for the code interpreter tool.
  const CodeInterpreterConfig({
    this.containerId,
    this.files,
  });

  /// Explicit container ID to reuse from a previous code_interpreter session.
  /// If not provided, uses 'auto' to create a new container or reuse an
  /// active one.
  final String? containerId;

  /// List of file IDs available to the code interpreter.
  /// Files must be uploaded through OpenAI's Files API first.
  final List<String>? files;

  /// Converts the configuration to a request JSON object.
  Map<String, dynamic> toRequestJson() {
    if (containerId != null && containerId!.isNotEmpty) {
      // Use explicit container ID
      return {
        'id': containerId,
        if (files != null && files!.isNotEmpty) 'files': files,
      };
    } else {
      // Use auto mode
      return {
        'type': 'auto',
        if (files != null && files!.isNotEmpty) 'files': files,
      };
    }
  }
}
