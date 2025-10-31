import 'package:json_schema/json_schema.dart';
import 'package:openai_core/openai_core.dart' as openai;

import '../../shared/openai_utils.dart';
import 'openai_responses_chat_options.dart';

/// Utilities for mapping Dartantic options to OpenAI Responses API types.
///
/// This class consolidates all option conversion logic for the OpenAI Responses
/// provider, keeping the chat model focused on streaming coordination.
class OpenAIResponsesOptionsMapper {
  OpenAIResponsesOptionsMapper._();

  /// Merges base and override metadata maps.
  ///
  /// Returns null if both inputs are null, otherwise combines them with
  /// override taking precedence.
  static Map<String, dynamic>? mergeMetadata(
    Map<String, dynamic>? base,
    Map<String, dynamic>? override,
  ) {
    if (base == null && override == null) return null;
    return {if (base != null) ...base, if (override != null) ...override};
  }

  /// Converts Dartantic reasoning configuration to OpenAI ReasoningOptions.
  ///
  /// Accepts either raw JSON map or typed enum values. Returns null if no
  /// reasoning configuration is specified.
  static openai.ReasoningOptions? toReasoningOptions({
    Map<String, dynamic>? raw,
    OpenAIReasoningEffort? effort,
    OpenAIReasoningSummary? summary,
  }) {
    openai.ReasoningEffort? resolvedEffort;
    openai.ReasoningDetail? resolvedSummary;

    if (raw != null && raw.isNotEmpty) {
      final parsed = openai.ReasoningOptions.fromJson(raw);
      resolvedEffort = parsed.effort;
      resolvedSummary = parsed.summary;
    }

    if (effort != null) {
      resolvedEffort = switch (effort) {
        OpenAIReasoningEffort.low => openai.ReasoningEffort.low,
        OpenAIReasoningEffort.medium => openai.ReasoningEffort.medium,
        OpenAIReasoningEffort.high => openai.ReasoningEffort.high,
      };
    }

    if (summary != null) {
      resolvedSummary = switch (summary) {
        OpenAIReasoningSummary.detailed => openai.ReasoningDetail.detailed,
        OpenAIReasoningSummary.concise => openai.ReasoningDetail.concise,
        OpenAIReasoningSummary.auto => openai.ReasoningDetail.auto,
        OpenAIReasoningSummary.none => null,
      };
    }

    if (resolvedEffort == null && resolvedSummary == null) {
      return null;
    }

    return openai.ReasoningOptions(
      effort: resolvedEffort,
      summary: resolvedSummary,
    );
  }

  /// Converts truncation strategy map to OpenAI Truncation enum.
  ///
  /// Returns null if raw is null or empty. Recognizes 'auto' and 'disabled'
  /// type values.
  static openai.Truncation? toTruncation(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) return null;
    final type = raw['type'];
    if (type is String) {
      switch (type) {
        case 'auto':
          return openai.Truncation.auto;
        case 'disabled':
          return openai.Truncation.disabled;
      }
    }
    return null;
  }

  /// Resolves text format from output schema or explicit response format.
  ///
  /// When outputSchema is provided, generates a JSON schema format with
  /// strict mode enabled. Otherwise delegates to the explicit responseFormat
  /// if provided.
  static openai.TextFormat? resolveTextFormat(
    JsonSchema? outputSchema,
    Map<String, dynamic>? responseFormat,
  ) {
    if (outputSchema != null) {
      final raw = outputSchema.schemaMap ?? const <String, dynamic>{};
      final schema = OpenAIUtils.prepareSchemaForOpenAI(
        Map<String, dynamic>.from(raw),
      );
      return openai.TextFormatJsonSchema(
        name: 'dartantic_output',
        schema: schema,
        description: schema['description'] as String?,
        strict: true,
      );
    }
    if (responseFormat == null) return null;
    return openai.TextFormat.fromJson(responseFormat);
  }
}
