import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:meta/meta.dart';

/// Options to pass into the Anthropic Chat Model.
@immutable
class AnthropicChatOptions extends ChatModelOptions {
  /// Creates a new Anthropic chat options instance.
  const AnthropicChatOptions({
    this.maxTokens,
    this.stopSequences,
    this.temperature,
    this.topK,
    this.topP,
    this.userId,
    this.thinkingEnabled = false,
    this.thinkingBudgetTokens,
  });

  /// The maximum number of tokens to generate before stopping.
  ///
  /// Note that our models may stop _before_ reaching this maximum. This
  /// parameter only specifies the absolute maximum number of tokens to
  /// generate.
  ///
  /// Different models have different maximum values for this parameter. See
  /// [models](https://docs.anthropic.com/en/docs/models-overview) for details.
  final int? maxTokens;

  /// Custom text sequences that will cause the model to stop generating.
  ///
  /// Anthropic models will normally stop when they have naturally completed
  /// their turn. If you want the model to stop generating when it encounters
  /// custom strings of text, you can use the `stopSequences` parameter.
  final List<String>? stopSequences;

  /// Amount of randomness injected into the response.
  ///
  /// Defaults to `1.0`. Ranges from `0.0` to `1.0`. Use `temperature` closer to
  /// `0.0` for analytical / multiple choice, and closer to `1.0` for creative
  /// and generative tasks.
  ///
  /// Note that even with `temperature` of `0.0`, the results will not be fully
  /// deterministic.
  final double? temperature;

  /// Only sample from the top K options for each subsequent token.
  ///
  /// Used to remove "long tail" low probability responses.
  /// [Learn more technical details here](https://towardsdatascience.com/how-to-sample-from-language-models-682bceb97277).
  ///
  /// Recommended for advanced use cases only. You usually only need to use
  /// `temperature`.
  final int? topK;

  /// Use nucleus sampling.
  ///
  /// In nucleus sampling, we compute the cumulative distribution over all the
  /// options for each subsequent token in decreasing probability order and cut
  /// it off once it reaches a particular probability specified by `top_p`. You
  /// should either alter `temperature` or `top_p`, but not both.
  ///
  /// Recommended for advanced use cases only. You usually only need to use
  /// `temperature`.
  final double? topP;

  /// An external identifier for the user who is associated with the request.
  ///
  /// This should be a uuid, hash value, or other opaque identifier. Anthropic
  /// may use this id to help detect abuse. Do not include any identifying
  /// information such as name, email address, or phone number.
  final String? userId;

  /// Enable Claude's extended thinking (chain-of-thought reasoning).
  ///
  /// When enabled, Claude shows its internal reasoning process before
  /// providing the final answer. Thinking content is exposed via:
  /// - During streaming: `ChatResult.metadata['thinking']` (incremental deltas)
  /// - In final result: Accumulated thinking in result metadata
  /// - In message history: Preserved in metadata when tool calls present
  ///
  /// **Anthropic-specific behavior**: When a response includes both thinking
  /// and tool calls, the thinking block is preserved in the message structure
  /// and sent back in subsequent turns. This is required by Anthropic's API
  /// to maintain proper context for multi-turn tool usage.
  ///
  /// Example:
  /// ```dart
  /// AnthropicChatOptions(
  ///   maxTokens: 16000,
  ///   thinkingEnabled: true,
  /// )
  /// ```
  ///
  /// Token costs:
  /// - Thinking tokens count toward your `max_tokens` limit
  /// - You are charged for all thinking tokens generated
  /// - Thinking blocks in conversation history also consume tokens
  ///
  /// See: https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking
  final bool thinkingEnabled;

  /// Optional token budget for thinking (defaults to 4096).
  ///
  /// Controls how many tokens Claude can use for its internal reasoning.
  /// Larger budgets enable more comprehensive reasoning.
  ///
  /// Anthropic recommends starting with lower values (4k-10k) and scaling up
  /// based on task complexity. If not specified, defaults to 4096 tokens.
  ///
  /// The Anthropic SDK validates minimum and maximum constraints based on
  /// their current API requirements.
  final int? thinkingBudgetTokens;
}
