import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dotprompt_dart/dotprompt_dart.dart';
import 'package:json_schema/json_schema.dart';

import '../message.dart';
import '../models/interface/model.dart';
import '../models/interface/model_settings.dart';
import '../providers/implementation/provider_table.dart';
import '../providers/interface/provider.dart';
import '../providers/interface/provider_caps.dart';
import '../providers/interface/provider_factory.dart';
import '../providers/interface/provider_settings.dart';
import 'agent_response.dart';
import 'embedding_type.dart';
import 'tool.dart';

export '../message.dart';
export 'agent_response.dart';
export 'embedding_type.dart';
export 'tool.dart';

/// An agent that can run prompts through an AI model and return responses.
///
/// This class provides a unified interface for interacting with different
/// AI model providers and handling both string and typed responses.
class Agent {
  /// Factory constructor to create an [Agent] for a specific model.
  ///
  /// Creates an [Agent] by specifying the model in the format "providerName",
  /// "providerName:modelName", or "providerName/modelName". Automatically
  /// resolves the appropriate provider for the given model.
  ///
  /// - [model]: The model identifier in "providerName",
  ///   "providerName:modelName", or "providerName/modelName" format.
  /// - [systemPrompt]: (Optional) A system prompt to guide the agent's
  ///   behavior.
  /// - [outputSchema]: (Optional) A [JsonSchema] defining the expected output
  ///   type.
  /// - [outputFromJson]: (Optional) A function to convert JSON output to a
  ///   typed object.
  /// - [tools]: (Optional) A collection of [Tool]s the agent can use.
  /// - [embeddingModel]: (Optional) The model name to use for embeddings. If
  ///   not provided, uses the provider's default embedding model.
  /// - [temperature]: (Optional) The temperature for the model.
  factory Agent(
    String model, {
    String? embeddingModel,
    String? apiKey,
    Uri? baseUrl,
    String? systemPrompt,
    JsonSchema? outputSchema,
    dynamic Function(Map<String, dynamic> json)? outputFromJson,
    Iterable<Tool>? tools,
    double? temperature,
  }) => Agent.provider(
    providerFor(
      model,
      embeddingModel: embeddingModel,
      apiKey: apiKey,
      baseUrl: baseUrl,
      temperature: temperature,
    ),
    systemPrompt: systemPrompt,
    outputSchema: outputSchema,
    outputFromJson: outputFromJson,
    tools: tools,
  );

  /// Creates a new [Agent] with the given [provider].
  ///
  /// - [provider]: The [Provider] to use for the agent.
  /// - [systemPrompt]: (Optional) The system prompt to use for the agent.
  /// - [outputSchema]: (Optional) The [JsonSchema] for the expected output
  ///   type.
  /// - [outputFromJson]: (Optional) A function to convert JSON output to a
  ///   typed object.
  /// - [tools]: (Optional) A collection of [Tool]s the agent can use.
  /// - [temperature]: (Optional) The temperature for the model.
  Agent.provider(
    Provider provider, {
    String? systemPrompt,
    JsonSchema? outputSchema,
    this.outputFromJson,
    Iterable<Tool>? tools,
    double? temperature,
  }) : assert(
         outputSchema == null ||
             provider.caps.contains(ProviderCaps.structuredOutput),
         'The provider [${provider.name}] is not capable of producing '
         'structured outputs.',
       ),
       _provider = provider,
       _systemPrompt = systemPrompt,
       _model = provider.createModel(
         ModelSettings(
           systemPrompt: systemPrompt,
           outputSchema: outputSchema,
           tools: tools,
           caps: provider.caps,
           temperature: temperature,
         ),
       ) {
    model = '${provider.name}:${_model.generativeModelName}';
  }

  /// A map of environment variables that can be used by providers.
  ///
  /// This provides a platform-agnostic way to set configuration, especially
  /// for API keys on the web, where traditional environment variables are not
  /// available.
  ///
  /// Example:
  /// ```dart
  /// Agent.environment['OPENAI_API_KEY'] = 'your_api_key';
  /// final agent = Agent('openai'); // no explicit apiKey needed!
  /// ```
  static final Map<String, String> environment = {};

  final Provider _provider;
  final Model _model;
  final String? _systemPrompt;

  /// Returns the model used by this agent in the format:
  ///   providerName:generativeModelName, e.g.
  ///   openai:gpt-4o
  ///   google:gemini-2.0-flash
  ///   openrouter:gpt-4o
  late String model;

  /// Function to convert JSON output to a typed object.
  ///
  /// When provided, this function is used to convert the JSON response from the
  /// model into a strongly-typed object when using [runFor].
  final dynamic Function(Map<String, dynamic> json)? outputFromJson;

  /// Helper to ensure the system prompt is present as the first message if
  /// needed. Some LLMs add the system prompt to the first message and some
  /// don't. By always adding it, we can be sure that the messages are
  /// consistent, at least wrt the system prompt.
  Iterable<Message> _ensureSystemPromptMessage(Iterable<Message> messages) =>
      messages.isNotEmpty &&
              _systemPrompt != null &&
              _systemPrompt.isNotEmpty &&
              messages.first.role != MessageRole.system
          ? [
            Message(role: MessageRole.system, parts: [TextPart(_systemPrompt)]),
            ...messages,
          ]
          : messages;

  /// Executes the given [prompt] using the model and returns the complete
  /// response.
  ///
  /// This method processes the prompt through the model, collects the output
  /// from the resulting stream, and returns it as a single [AgentResponse].
  ///
  /// - [prompt]: The input string to be processed by the model.
  ///
  /// Returns an [AgentResponse] containing the concatenated output from the
  /// model.
  Future<AgentResponse> run(
    String prompt, {
    Iterable<Message> messages = const [],
    Iterable<Part> attachments = const [],
  }) async {
    final stream = runStream(
      prompt,
      messages: messages,
      attachments: attachments,
    );

    final output = StringBuffer();
    var outputMessages = <Message>[];
    await for (final chunk in stream) {
      output.write(chunk.output);
      outputMessages = chunk.messages;
    }

    return AgentResponse(output: output.toString(), messages: outputMessages);
  }

  /// Runs the given [prompt] through the model and returns the response as a
  /// stream.
  ///
  /// Returns a [Stream] of [AgentResponse] containing the raw string output.
  Stream<AgentResponse> runStream(
    String prompt, {
    Iterable<Message> messages = const [],
    Iterable<Part> attachments = const [],
  }) async* {
    await for (final chunk in _model.runStream(
      prompt: prompt,
      messages: messages,
      attachments: attachments,
    )) {
      yield AgentResponse(
        output: chunk.output,
        messages: _ensureSystemPromptMessage(chunk.messages),
      );
    }
  }

  /// Runs the given [prompt] through the model and returns a typed response.
  ///
  /// Returns an [AgentResponseFor<T>] containing the output converted to type
  /// [T]. Uses [outputFromJson] to convert the JSON response if provided,
  /// otherwise returns the decoded JSON.
  Future<AgentResponseFor<T>> runFor<T>(
    String prompt, {
    Iterable<Message> messages = const [],
    Iterable<Part> attachments = const [],
  }) async {
    final response = await run(
      prompt,
      messages: messages,
      attachments: attachments,
    );

    final outputJson = jsonDecode(response.output);
    final typedOutput = outputFromJson?.call(outputJson) ?? outputJson;
    return AgentResponseFor(output: typedOutput, messages: response.messages);
  }

  /// Executes a given [DotPrompt] and returns the complete response.
  ///
  /// This method processes the [DotPrompt] through the model specified in the
  /// prompt's front matter or defaults to 'google' if not specified. It
  /// collects the output and returns it as a single [AgentResponse].
  ///
  /// - [prompt]: The [DotPrompt] to be executed.
  /// - [systemPrompt]: (Optional) A system prompt to guide the agent's
  ///   behavior.
  /// - [outputSchema]: (Optional) A [JsonSchema] defining the expected output
  ///   type.
  /// - [outputFromJson]: (Optional) A function to convert JSON output to a
  ///   typed object.
  /// - [tools]: (Optional) A collection of [Tool]s the agent can use.
  /// - [input]: (Optional) A map of input values to render the prompt with.
  ///   Defaults to an empty map.
  ///
  /// Returns a [Future] of [AgentResponse] containing the concatenated output
  /// from the agent.
  static Future<AgentResponse> runPrompt(
    DotPrompt prompt, {
    String? systemPrompt,
    JsonSchema? outputSchema,
    dynamic Function(Map<String, dynamic> json)? outputFromJson,
    Iterable<Tool>? tools,
    Map<String, dynamic> input = const {},
    Iterable<Message> messages = const [],
    Iterable<Part> attachments = const [],
  }) => Agent(
    prompt.frontMatter.model ?? 'google',
    systemPrompt: systemPrompt,
    outputSchema: outputSchema,
    outputFromJson: outputFromJson,
    tools: tools,
  ).run(prompt.render(input), messages: messages, attachments: attachments);

  /// Executes a [DotPrompt] and returns a typed response.
  ///
  /// This method processes the [DotPrompt] through the model specified in the
  /// prompt's front matter, or defaults to 'google' if not specified. It
  /// renders the prompt with the provided [input] map, sends it to the model,
  /// and returns the output as an [AgentResponseFor<T>] containing the output
  /// converted to type [T].
  ///
  /// - [prompt]: The [DotPrompt] to execute.
  /// - [systemPrompt]: (Optional) A system prompt to guide the agent's
  ///   behavior.
  /// - [outputSchema]: (Optional) A [JsonSchema] defining the expected output
  ///   type.
  /// - [outputFromJson]: (Optional) A function to convert JSON output to a
  ///   typed object.
  /// - [tools]: (Optional) A collection of [Tool]s the agent can use.
  /// - [input]: (Optional) A map of input values to render the prompt with.
  ///   Defaults to an empty map.
  ///
  /// Returns a [Future] of [AgentResponseFor<T>] containing the output
  /// converted to type [T].
  static Future<AgentResponseFor<T>> runPromptFor<T>(
    DotPrompt prompt, {
    String? systemPrompt,
    JsonSchema? outputSchema,
    dynamic Function(Map<String, dynamic> json)? outputFromJson,
    Iterable<Tool>? tools,
    Map<String, dynamic> input = const {},
    Iterable<Message> messages = const [],
    Iterable<Part> attachments = const [],
  }) => Agent(
    prompt.frontMatter.model ?? 'google',
    systemPrompt: systemPrompt,
    outputSchema: outputSchema,
    outputFromJson: outputFromJson,
    tools: tools,
  ).runFor<T>(
    prompt.render(input),
    messages: messages,
    attachments: attachments,
  );

  /// Executes a given [DotPrompt] using the specified parameters and returns
  /// the response as a [Stream] of [AgentResponse].
  ///
  /// - [prompt]: The [DotPrompt] to be executed.
  /// - [systemPrompt]: (Optional) A system prompt to guide the agent's
  ///   behavior.
  /// - [outputSchema]: (Optional) A [JsonSchema] defining the expected output
  ///   type.
  /// - [outputFromJson]: (Optional) A function to convert JSON output to a
  ///   typed object.
  /// - [tools]: (Optional) A collection of [Tool]s the agent can use.
  /// - [input]: (Optional) A map of input values to render the prompt with.
  ///   Defaults to an empty map.
  ///
  /// Returns a [Stream] of [AgentResponse] containing the raw string output
  /// from the agent.
  static Stream<AgentResponse> runPromptStream(
    DotPrompt prompt, {
    String? systemPrompt,
    JsonSchema? outputSchema,
    dynamic Function(Map<String, dynamic> json)? outputFromJson,
    Iterable<Tool>? tools,
    Map<String, dynamic> input = const {},
    Iterable<Message> messages = const [],
    Iterable<Part> attachments = const [],
  }) => Agent(
    prompt.frontMatter.model ?? 'google',
    systemPrompt: systemPrompt,
    outputSchema: outputSchema,
    outputFromJson: outputFromJson,
    tools: tools,
  ).runStream(
    prompt.render(input),
    messages: messages,
    attachments: attachments,
  );

  /// Generates vector embeddings for the given text.
  ///
  /// This method creates numerical vector representations of text that can be
  /// used for similarity search, clustering, and other semantic operations.
  ///
  /// Uses the embedding model specified in the Agent constructor, or the
  /// provider's default embedding model if none was specified.
  ///
  /// - [text]: The text to generate embeddings for.
  /// - [type]: The type of embedding to generate (document or query).
  ///   Defaults to [EmbeddingType.document].
  /// - [dimensions]: (Optional) The number of dimensions for the embedding.
  ///
  /// Returns a [Future] containing a Float64List representing the
  /// embedding vector.
  ///
  /// Throws [UnsupportedError] if the underlying model/provider doesn't
  /// support embedding generation.
  Future<Float64List> createEmbedding(
    String text, {
    EmbeddingType type = EmbeddingType.document,
    int? dimensions,
  }) => _model.createEmbedding(text, type: type, dimensions: dimensions);

  /// Returns a map of all available providers.
  ///
  /// The keys are the provider names, and the values are the provider
  /// factories.
  ///
  /// The provider factories are used to create instances of the providers.
  static Map<String, ProviderFactory> get providers => ProviderTable.providers;

  /// Resolves the [Provider] for the given [model] string.
  ///
  /// [model] should be in the format "providerName", "providerName:modelName",
  /// or "providerName/modelName".
  /// [embeddingModel] is optional and specifies the embedding model to use.
  /// [apiKey] is optional and specifies the API key for authentication.
  /// [baseUrl] is optional and specifies the base URL for the provider.
  /// [temperature] is optional and specifies the temperature for the provider.
  ///
  /// Throws [ArgumentError] if [model] is empty.
  static Provider providerFor(
    String model, {
    String? embeddingModel,
    String? apiKey,
    Uri? baseUrl,
    double? temperature,
  }) {
    if (model.isEmpty) throw ArgumentError('Model must not be empty');

    final index = model.indexOf(RegExp('[:/]'));
    final providerName = index == -1 ? model : model.substring(0, index);
    final modelName = index == -1 ? null : model.substring(index + 1);

    return ProviderTable.providerFor(
      providerName,
      settings: ProviderSettings(
        modelName: modelName,
        embeddingModelName: embeddingModel,
        apiKey: apiKey,
        baseUrl: baseUrl,
      ),
    );
  }

  /// Returns the [limit] items with highest cosine similarity to
  /// [queryEmbedding].
  ///
  /// This method performs semantic similarity search by:
  /// 1. Computing cosine similarity between the query and each item's embedding
  /// 2. Ranking all items by similarity score (1.0 = identical, 0.0 =
  ///    orthogonal, -1.0 = opposite)
  /// 3. Returning the [limit] most similar items
  ///
  /// Cosine similarity measures the angle between two vectors, making it ideal
  /// for semantic similarity since it's invariant to vector magnitude.
  static Iterable<T> findTopMatches<T>({
    required Map<T, Float64List> embeddingMap,
    required Float64List queryEmbedding,
    int limit = 1,
  }) {
    if (embeddingMap.isEmpty) {
      throw ArgumentError('embeddingMap cannot be empty');
    }

    // Store query dimensions and pre-compute its magnitude for efficiency
    // (we'll reuse this for every similarity calculation)
    final dim = queryEmbedding.length;
    final queryMagnitude = _magnitude(queryEmbedding);

    // Calculate cosine similarity score for each item in the embedding map
    final scoredItems =
        embeddingMap.entries.map((entry) {
          final embedding = entry.value;

          // Ensure all embeddings have the same dimensionality
          if (embedding.length != dim) {
            throw ArgumentError(
              'Mismatched embedding dimension for item: ${entry.key}',
            );
          }

          // Compute cosine similarity: dot(a,b) / (||a|| * ||b||)
          // Higher scores indicate greater semantic similarity
          final score = _cosineSimilarityWithMagnitudeA(
            queryEmbedding,
            queryMagnitude,
            embedding,
          );
          return MapEntry(entry.key, score);
        }).toList();

    // Sort by similarity score in descending order (best matches first)
    scoredItems.sort((a, b) => b.value.compareTo(a.value));

    // Return the top K most similar items
    return scoredItems.take(limit).map((e) => e.key).toList();
  }

  /// Computes cosine similarity between two vectors.
  ///
  /// Cosine similarity = dot(a,b) / (||a|| * ||b||)
  ///
  /// Returns a value between -1.0 and 1.0:
  /// - 1.0: vectors point in the same direction (identical)
  /// - 0.0: vectors are orthogonal (unrelated)
  /// - -1.0: vectors point in opposite directions
  static double cosineSimilarity(Float64List a, Float64List b) {
    assert(a.length == b.length);
    final dot = dotProduct(a, b);
    final magnitudeA = _magnitude(a);
    final magnitudeB = _magnitude(b);
    return dot / (magnitudeA * magnitudeB); // Normalize by both magnitudes
  }

  /// Computes cosine similarity between two vectors with pre-computed magnitude
  /// for [a].
  ///
  /// Cosine similarity = dot(a,b) / (||a|| * ||b||)
  /// This optimized version takes the pre-computed magnitude of vector [a]
  /// to avoid redundant calculations when comparing one query against many
  /// items.
  ///
  /// Returns a value between -1.0 and 1.0:
  /// - 1.0: vectors point in the same direction (identical)
  /// - 0.0: vectors are orthogonal (unrelated)
  /// - -1.0: vectors point in opposite directions
  static double _cosineSimilarityWithMagnitudeA(
    Float64List a,
    double magnitudeA,
    Float64List b,
  ) {
    assert(a.length == b.length);
    final dot = dotProduct(a, b);
    final magnitudeB = _magnitude(b);
    return dot / (magnitudeA * magnitudeB); // Normalize by both magnitudes
  }

  /// Computes the dot product (scalar product) of two vectors.
  ///
  /// The dot product measures how much two vectors "align" with each other.
  /// For vectors a and b: `dot(a,b) = sum(a[i] * b[i])` for all dimensions i.
  ///
  /// This is a key component in cosine similarity calculation.
  static double dotProduct(Float64List a, Float64List b) {
    assert(a.length == b.length);

    // Sum the element-wise products across all dimensions
    var sum = 0.0;
    for (var i = 0; i < a.length; ++i) {
      sum += a[i] * b[i];
    }

    return sum;
  }

  /// Computes the Euclidean magnitude (L2 norm) of a vector.
  ///
  /// The magnitude represents the "length" of the vector in n-dimensional
  /// space.
  /// Formula: `||v|| = sqrt(sum(v[i]^2))` for all dimensions i.
  ///
  /// This is used to normalize vectors in cosine similarity calculations,
  /// making the similarity independent of vector magnitude.
  static double _magnitude(Float64List v) {
    // Sum the squared values of all vector components
    var sum = 0.0;
    for (var i = 0; i < v.length; ++i) {
      sum += v[i] * v[i];
    }

    return sqrt(sum); // Return the square root to get the magnitude
  }

  /// The capabilities of this agent's model.
  Set<ProviderCaps> get caps => _model.caps;

  /// Lists all available models from this provider.
  Future<Iterable<ModelInfo>> listModels() => _provider.listModels();
}
