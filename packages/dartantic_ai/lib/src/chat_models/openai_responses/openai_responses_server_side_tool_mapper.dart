import 'package:logging/logging.dart';
import 'package:openai_core/openai_core.dart' as openai;

import 'openai_responses_chat_options.dart';
import 'openai_responses_server_side_tools.dart';

/// Maps Dartantic server-side tool configurations to OpenAI Responses API payloads.
class OpenAIResponsesServerSideToolMapper {
  OpenAIResponsesServerSideToolMapper._();

  static final Logger _logger = Logger(
    'dartantic.chat.models.openai_responses.server_side_tool_mapper',
  );

  /// Converts dartantic tool preferences into OpenAI Responses tool payloads.
  static List<openai.Tool> buildServerSideTools({
    required Set<OpenAIServerSideTool> serverSideTools,
    FileSearchConfig? fileSearchConfig,
    WebSearchConfig? webSearchConfig,
    CodeInterpreterConfig? codeInterpreterConfig,
    ImageGenerationConfig? imageGenerationConfig,
  }) {
    if (serverSideTools.isEmpty) return const [];

    final tools = <openai.Tool>[];

    for (final tool in serverSideTools) {
      switch (tool) {
        case OpenAIServerSideTool.webSearch:
          final config = webSearchConfig;
          tools.add(
            openai.WebSearchPreviewTool(
              searchContextSize: _mapSearchContextSize(config?.contextSize),
              userLocation: _mapUserLocation(config?.location),
            ),
          );
          continue;
        case OpenAIServerSideTool.fileSearch:
          final config = fileSearchConfig;
          if (config == null) {
            _logger.warning(
              'File search tool requested but no FileSearchConfig provided; '
              'skipping.',
            );
            continue;
          }
          if (!config.hasVectorStores) {
            _logger.warning(
              'File search tool requested but no vectorStoreIds provided; '
              'skipping.',
            );
            continue;
          }

          openai.FileSearchFilter? parsedFilter;
          if (config.filters != null && config.filters!.isNotEmpty) {
            parsedFilter = openai.FileSearchFilter.fromJson(
              Map<String, dynamic>.from(config.filters!),
            );
          }

          openai.RankingOptions? rankingOptions;
          if (config.ranker != null || config.scoreThreshold != null) {
            rankingOptions = openai.RankingOptions(
              ranker: config.ranker,
              scoreThreshold: config.scoreThreshold,
            );
          }

          tools.add(
            openai.FileSearchTool(
              vectorStoreIds: config.vectorStoreIds,
              filters: parsedFilter == null ? null : [parsedFilter],
              maxNumResults: config.maxResults,
              rankingOptions: rankingOptions,
            ),
          );
          continue;
        case OpenAIServerSideTool.imageGeneration:
          final config = imageGenerationConfig ?? const ImageGenerationConfig();
          tools.add(
            openai.ImageGenerationTool(
              partialImages: config.partialImages,
              quality: _mapImageQuality(config.quality),
              imageOutputSize: _mapImageSize(config.size),
            ),
          );
          continue;
        case OpenAIServerSideTool.codeInterpreter:
          final config = codeInterpreterConfig;
          openai.CodeInterpreterContainer container;
          if (config != null && config.shouldReuseContainer) {
            container = openai.CodeInterpreterContainerId(config.containerId!);
          } else {
            container = openai.CodeInterpreterContainerAuto(
              fileIds: config?.fileIds,
            );
          }
          tools.add(openai.CodeInterpreterTool(container: container));
          continue;
      }
    }

    return tools;
  }

  static openai.SearchContextSize? _mapSearchContextSize(
    WebSearchContextSize? size,
  ) {
    switch (size) {
      case WebSearchContextSize.low:
        return openai.SearchContextSize.low;
      case WebSearchContextSize.medium:
        return openai.SearchContextSize.medium;
      case WebSearchContextSize.high:
        return openai.SearchContextSize.high;
      case WebSearchContextSize.other:
        return openai.SearchContextSize.other;
      case null:
        return null;
    }
  }

  static openai.UserLocation? _mapUserLocation(WebSearchLocation? location) {
    if (location == null || location.isEmpty) return null;
    return openai.UserLocation(
      city: location.city,
      region: location.region,
      country: location.country,
      timezone: location.timezone,
    );
  }

  static openai.ImageOutputQuality _mapImageQuality(
    ImageGenerationQuality quality,
  ) => switch (quality) {
    ImageGenerationQuality.low => openai.ImageOutputQuality.low,
    ImageGenerationQuality.medium => openai.ImageOutputQuality.medium,
    ImageGenerationQuality.high => openai.ImageOutputQuality.high,
    ImageGenerationQuality.auto => openai.ImageOutputQuality.auto,
  };

  static openai.ImageOutputSize _mapImageSize(ImageGenerationSize size) =>
      switch (size) {
        ImageGenerationSize.auto => openai.ImageOutputSize.auto,
        ImageGenerationSize.square256 => openai.ImageOutputSize.square256,
        ImageGenerationSize.square512 => openai.ImageOutputSize.square512,
        ImageGenerationSize.square1024 => openai.ImageOutputSize.square1024,
        ImageGenerationSize.landscape1536x1024 =>
          openai.ImageOutputSize.landscape1536x1024,
        ImageGenerationSize.landscape1792x1024 =>
          openai.ImageOutputSize.landscape1792x1024,
        ImageGenerationSize.portrait1024x1536 =>
          openai.ImageOutputSize.portrait1024x1536,
        ImageGenerationSize.portrait1024x1792 =>
          openai.ImageOutputSize.portrait1024x1792,
      };
}
