import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../chat_models/chat_utils.dart';

/// Shared utilities for OpenAI and OpenAI-compatible providers.
class OpenAIUtils {
  OpenAIUtils._();

  /// Prepares a JsonSchema for OpenAI's structured output mode.
  ///
  /// OpenAI requires:
  /// - additionalProperties: false at every object level (if strict)
  /// - format field removed from all properties
  /// - required array with ALL property keys for objects (strict mode)
  static Map<String, dynamic> prepareSchemaForOpenAI(
    Map<String, dynamic> schema, {
    bool strict = true,
  }) {
    final result = Map<String, dynamic>.from(schema);

    // Handle type arrays (e.g., ['string', 'null'])
    if (result['type'] is List) {
      final types = result['type'] as List;
      // If it's a nullable type, just use the non-null type
      final nonNullTypes = types.where((t) => t != 'null').toList();
      if (nonNullTypes.length == 1) {
        result['type'] = nonNullTypes.first;
      }
    }

    // Remove format field if present
    result.remove('format');

    // If this is an object, ensure additionalProperties: false and
    // required array
    if (result['type'] == 'object') {
      if (strict) {
        result['additionalProperties'] = false;
      }

      // Recursively process properties
      final properties = result['properties'] as Map<String, dynamic>?;
      if (properties != null && properties.isNotEmpty) {
        final processedProperties = <String, dynamic>{};
        for (final entry in properties.entries) {
          processedProperties[entry.key] = prepareSchemaForOpenAI(
            entry.value as Map<String, dynamic>,
            strict: strict,
          );
        }
        result['properties'] = processedProperties;

        // OpenAI's strict mode requires ALL properties to be in the required
        // array. This is a limitation of their API, not a bug in our code
        if (strict) {
          result['required'] = properties.keys.toList();
        }
      } else {
        // For empty objects, ensure we have an empty properties map
        result['properties'] = <String, dynamic>{};
        result['required'] = <String>[];
      }
    }

    // Process array items
    if (result['type'] == 'array') {
      final items = result['items'] as Map<String, dynamic>?;
      if (items != null) {
        result['items'] = prepareSchemaForOpenAI(items, strict: strict);
      }
    }

    // Process definitions if present
    final definitions = result['definitions'] as Map<String, dynamic>?;
    if (definitions != null) {
      final processedDefinitions = <String, dynamic>{};
      for (final entry in definitions.entries) {
        processedDefinitions[entry.key] = prepareSchemaForOpenAI(
          entry.value as Map<String, dynamic>,
          strict: strict,
        );
      }
      result['definitions'] = processedDefinitions;
    }

    return result;
  }

  /// Lists models from an OpenAI-compatible API endpoint.
  static Stream<ModelInfo> listOpenAIModels({
    required Uri baseUrl,
    required String providerName,
    required Logger logger,
    String? apiKey,
    Map<String, String>? headers,
  }) async* {
    final url = appendPath(baseUrl, 'models');
    final requestHeaders = <String, String>{
      if (apiKey != null && apiKey.isNotEmpty)
        'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      ...?headers,
    };

    logger.info('Fetching models from $url');

    try {
      final response = await http.get(url, headers: requestHeaders);
      if (response.statusCode != 200) {
        logger.warning(
          'Failed to fetch models: HTTP ${response.statusCode}, '
          'body: ${response.body}',
        );
        throw Exception('Failed to fetch models: ${response.body}');
      }

      final data = jsonDecode(response.body);

      // Handle both list and object with 'data' field formats
      final models = data is List
          ? data
          : data is Map<String, dynamic>
          ? data['data'] as List<dynamic>? ?? const []
          : const [];

      for (final model in models) {
        if (model is! Map<String, dynamic>) continue;
        final id = model['id'] as String?;
        if (id == null) continue;

        final kinds = inferModelKinds(model);
        yield ModelInfo(
          name: id,
          providerName: providerName,
          kinds: kinds,
          description: model['object']?.toString(),
          extra: model,
        );
      }

      final modelCount = models.length;
      logger.info('Successfully fetched $modelCount models');
    } catch (e) {
      logger.severe('Error fetching models: $e');
      rethrow;
    }
  }

  /// Infers model capabilities from OpenAI model metadata.
  static Set<ModelKind> inferModelKinds(Map<String, dynamic> model) {
    final id = model['id']?.toString() ?? '';
    final object = model['object']?.toString() ?? '';
    final kinds = <ModelKind>{};

    // Check for embeddings models
    if (id.contains('embedding')) {
      kinds.add(ModelKind.embeddings);
    }

    // Check for TTS models
    if (id.contains('tts')) {
      kinds.add(ModelKind.tts);
    }

    // Check for vision/image models
    if (id.contains('vision') || id.contains('image')) {
      kinds.add(ModelKind.image);
      kinds.add(ModelKind.media);
    }

    // Check for audio models
    if (id.contains('audio') || id.contains('whisper')) {
      kinds.add(ModelKind.audio);
    }

    // Check for token counting models
    if (id.contains('count-tokens')) {
      kinds.add(ModelKind.countTokens);
    }

    // Most models are chat if not otherwise classified
    // Check common chat model patterns
    if (!kinds.contains(ModelKind.embeddings)) {
      if (object == 'model' ||
          id.contains('gpt') ||
          id.contains('chat') ||
          id.contains('claude') ||
          id.contains('mixtral') ||
          id.contains('llama') ||
          id.contains('command') ||
          id.contains('sonnet') ||
          id.contains('o1') ||
          id.contains('turbo')) {
        kinds.add(ModelKind.chat);
      }
    }

    // Default to 'other' if we can't determine the kind
    if (kinds.isEmpty) {
      kinds.add(ModelKind.other);
    }

    return kinds;
  }
}
