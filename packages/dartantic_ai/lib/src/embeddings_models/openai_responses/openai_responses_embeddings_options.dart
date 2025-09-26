import 'package:dartantic_interface/dartantic_interface.dart';

/// Options for configuring the OpenAI Responses embeddings model.
class OpenAIResponsesEmbeddingsOptions extends EmbeddingsModelOptions {
  /// Creates a new set of embeddings options for the OpenAI Responses API.
  const OpenAIResponsesEmbeddingsOptions({
    super.dimensions,
    super.batchSize,
    this.user,
    this.encodingFormat,
    this.extraBody,
  });

  /// A unique identifier representing your end-user, which can help OpenAI to
  /// monitor and detect abuse.
  final String? user;

  /// Allows selecting a non-default encoding format for the output vector.
  final String? encodingFormat;

  /// Additional request payload forwarded to the Responses API.
  final Map<String, dynamic>? extraBody;
}
