import 'dart:typed_data';

import '../../agent/agent.dart';
import '../../providers/interface/provider_caps.dart';

/// Abstract interface for AI model implementations.
///
/// Defines the contract that all model implementations must follow to
/// support running prompts and receiving responses.
abstract class Model {
  /// The model name of this model, e.g. "gpt-4".
  String get generativeModelName;

  /// The embedding model name of this model, e.g. "text-embedding-3-small".
  String get embeddingModelName;

  /// Runs the given [prompt] through the model and returns the response.
  ///
  /// Returns an [AgentResponse] containing the model's output.
  Stream<AgentResponse> runStream({
    required String prompt,
    required Iterable<Message> messages,
    required Iterable<Part> attachments,
  });

  /// Generates an embedding vector for the given [text].
  ///
  /// The [type] parameter specifies whether this embedding is for a document
  /// (content to be stored and searched) or a query (search input).
  ///
  /// Returns a Float64List of floating-point values representing the text's
  /// position in high-dimensional semantic space, suitable for similarity
  /// calculations.
  ///
  /// The [dimensions] parameter specifies the number of dimensions to
  /// return. If not provided, the model will use its default dimensionality.
  Future<Float64List> createEmbedding(
    String text, {
    EmbeddingType type = EmbeddingType.document,
    int? dimensions,
  });

  /// The capabilities of this model.
  Set<ProviderCaps> get caps;
}
