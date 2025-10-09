import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:meta/meta.dart';
import 'package:openai_core/openai_core.dart';

import 'openai_responses_server_side_tools.dart';

/// Options for configuring the OpenAI Responses chat model.
@immutable
class OpenAIResponsesChatModelOptions extends ChatModelOptions {
  /// Creates a new set of options for the OpenAI Responses chat model.
  const OpenAIResponsesChatModelOptions({
    this.temperature,
    this.topP,
    this.maxOutputTokens,
    this.store,
    this.metadata,
    this.include,
    this.parallelToolCalls,
    this.toolChoice,
    this.reasoning,
    this.reasoningEffort,
    this.reasoningSummary,
    this.responseFormat,
    this.truncationStrategy,
    this.user,
    this.imageDetail,
    this.serverSideTools,
    this.fileSearchConfig,
    this.webSearchConfig,
    this.codeInterpreterConfig,
    this.imageGenerationConfig,
  });

  /// Sampling temperature passed to the Responses API.
  final double? temperature;

  /// Nucleus sampling parameter (top_p) passed to the Responses API.
  final double? topP;

  /// Maximum number of output tokens allowed for the response.
  final int? maxOutputTokens;

  /// Whether Responses session state should be persisted by the server.
  final bool? store;

  /// Additional metadata forwarded to the Responses API.
  final Map<String, dynamic>? metadata;

  /// Specific response fields to include from the Responses API.
  final List<String>? include;

  /// Whether the model may call multiple tools in parallel.
  final bool? parallelToolCalls;

  /// Controls which tool (if any) is chosen by the model.
  final dynamic toolChoice;

  /// Reasoning configuration block for the Responses API.
  final Map<String, dynamic>? reasoning;

  /// Preferred reasoning effort for models that expose thinking controls.
  final OpenAIReasoningEffort? reasoningEffort;

  /// Preferred reasoning summary verbosity (where supported).
  final OpenAIReasoningSummary? reasoningSummary;

  /// Response formatting hints for the Responses API.
  final Map<String, dynamic>? responseFormat;

  /// Truncation configuration dictionary for the Responses API.
  final Map<String, dynamic>? truncationStrategy;

  /// End-user identifier for abuse monitoring.
  final String? user;

  /// Preferred detail level when encoding image inputs.
  final ImageDetail? imageDetail;

  /// Server-side Responses tools that should be enabled for this call.
  final Set<OpenAIServerSideTool>? serverSideTools;

  /// Additional configuration for the `file_search` server-side tool.
  final FileSearchConfig? fileSearchConfig;

  /// Additional configuration for the `web_search` server-side tool.
  final WebSearchConfig? webSearchConfig;

  /// Additional configuration for the `code_interpreter` server-side tool.
  final CodeInterpreterConfig? codeInterpreterConfig;

  /// Additional configuration for the `image_generation` server-side tool.
  final ImageGenerationConfig? imageGenerationConfig;
}

/// Reasoning effort levels for OpenAI Responses models that support thinking.
enum OpenAIReasoningEffort {
  /// Low reasoning effort (fastest, least detailed).
  low,

  /// Balanced reasoning effort (default behaviour).
  medium,

  /// Highest reasoning effort (slowest, most detailed).
  high,
}

/// Reasoning summary verbosity preference for OpenAI Responses.
enum OpenAIReasoningSummary {
  /// Request a detailed reasoning summary.
  detailed,

  /// Request a concise reasoning summary.
  concise,

  /// Allow the model to pick the best summary granularity.
  auto,

  /// Do not request a reasoning summary channel.
  none,
}

/// Configuration for the image_generation server-side tool.
@immutable
class ImageGenerationConfig {
  /// Creates a new image generation configuration.
  const ImageGenerationConfig({
    this.partialImages = 0,
    this.quality = ImageGenerationQuality.auto,
    this.size = ImageGenerationSize.auto,
  });

  /// Number of partial/preview images to generate during streaming (0-3).
  /// - 0: No progressive previews, only final image (default)
  /// - 1-3: Show intermediate render stages during generation
  /// Higher values show more progressive rendering but use more bandwidth.
  final int partialImages;

  /// Image quality setting.
  /// Default is auto, which lets the model choose the best quality.
  final ImageGenerationQuality quality;

  /// Output image size.
  /// Default is auto, which lets the model choose the appropriate size.
  final ImageGenerationSize size;
}

/// Quality levels for image generation.
enum ImageGenerationQuality {
  /// Low quality (fastest generation).
  low,

  /// Medium quality (balanced speed/quality).
  medium,

  /// High quality (slowest, best quality).
  high,

  /// Automatic quality selection.
  auto,
}

/// Size options for generated images.
enum ImageGenerationSize {
  /// Automatic size selection.
  auto,

  /// Square 256x256 (DALL·E-2 only).
  square256,

  /// Square 512x512 (DALL·E-2 only).
  square512,

  /// Square 1024x1024 (all models).
  square1024,

  /// Landscape 1536x1024 (gpt-image-1).
  landscape1536x1024,

  /// Landscape 1792x1024 (DALL·E-3).
  landscape1792x1024,

  /// Portrait 1024x1536 (gpt-image-1).
  portrait1024x1536,

  /// Portrait 1024x1792 (DALL·E-3).
  portrait1024x1792,
}
