import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:meta/meta.dart';

/// Options to pass into LlamaCpp.
@immutable
class LlamaCppChatOptions extends ChatModelOptions {
  /// Creates a new llama_cpp chat options instance.
  const LlamaCppChatOptions({
    this.seed,
    this.topK,
    this.topP,
    this.minP,
    this.tfsZ,
    this.typicalP,
    this.temperature,
    this.repeatPenalty,
    this.repeatLastN,
    this.penalizeNl,
    this.presencePenalty,
    this.frequencyPenalty,
    this.mirostat,
    this.mirostatTau,
    this.mirostatEta,
    this.penalizeEos,
    this.stop,
    this.nPredict,
    this.nKeep,
    this.nProbs,
    this.minKeep,
  });

  /// Random seed for reproducibility.
  final int? seed;

  /// Top-K sampling parameter.
  final int? topK;

  /// Top-P (nucleus) sampling parameter.
  final double? topP;

  /// Minimum probability for a token to be considered.
  final double? minP;

  /// Tail free sampling parameter.
  final double? tfsZ;

  /// Typical sampling parameter.
  final double? typicalP;

  /// Temperature for sampling.
  final double? temperature;

  /// Repetition penalty.
  final double? repeatPenalty;

  /// Number of tokens to consider for repeat penalty.
  final int? repeatLastN;

  /// Whether to penalize newlines.
  final bool? penalizeNl;

  /// Presence penalty.
  final double? presencePenalty;

  /// Frequency penalty.
  final double? frequencyPenalty;

  /// Mirostat sampling mode (0 = disabled, 1 = v1, 2 = v2).
  final int? mirostat;

  /// Mirostat target entropy (tau).
  final double? mirostatTau;

  /// Mirostat learning rate (eta).
  final double? mirostatEta;

  /// Whether to penalize end-of-sequence token.
  final bool? penalizeEos;

  /// List of stop sequences.
  final List<String>? stop;

  /// Maximum number of tokens to predict.
  final int? nPredict;

  /// Number of tokens to keep from initial prompt.
  final int? nKeep;

  /// Number of probability values to return.
  final int? nProbs;

  /// Minimum number of tokens to keep.
  final int? minKeep;
}
