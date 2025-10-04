import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import 'finish_reason.dart';
import 'language_model_usage.dart';

/// Result returned by the model.
@immutable
abstract class LanguageModelResult<TOutput extends Object> {
  /// Creates a new language model result instance.
  LanguageModelResult({
    required this.output,
    required this.finishReason,
    required this.metadata,
    this.usage,
    String? id,
  }) : id = id ?? const Uuid().v4();

  /// Result id.
  final String id;

  /// Generated output.
  final TOutput output;

  /// The reason the model stopped generating tokens.
  final FinishReason finishReason;

  /// Other metadata about the generation.
  final Map<String, dynamic> metadata;

  ///  Usage stats for the generation.
  final LanguageModelUsage? usage;
}
