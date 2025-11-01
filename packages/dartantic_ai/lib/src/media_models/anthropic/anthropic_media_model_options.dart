import 'package:dartantic_interface/dartantic_interface.dart';

import '../../chat_models/anthropic_chat/anthropic_chat_options.dart';

/// Options for configuring Anthropic media generation runs.
class AnthropicMediaModelOptions extends MediaGenerationModelOptions {
  /// Creates a new set of media options.
  const AnthropicMediaModelOptions({
    this.maxTokens,
    this.stopSequences,
    this.temperature,
    this.topK,
    this.topP,
    this.userId,
    this.thinkingBudgetTokens,
    this.serverTools,
  });

  /// Maximum number of output tokens for the Anthropic request.
  final int? maxTokens;

  /// Stop sequences that should end generation early.
  final List<String>? stopSequences;

  /// Sampling temperature (0.0-1.0).
  final double? temperature;

  /// Top-K sampling parameter.
  final int? topK;

  /// Top-P sampling parameter.
  final double? topP;

  /// Optional user identifier forwarded to Anthropic.
  final String? userId;

  /// Budget for Anthropic thinking tokens when enabled.
  final int? thinkingBudgetTokens;

  /// Additional server-side tools to enable alongside code execution.
  final List<AnthropicServerToolConfig>? serverTools;
}
