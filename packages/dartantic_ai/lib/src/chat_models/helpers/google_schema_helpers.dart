import 'package:google_cloud_ai_generativelanguage_v1beta/generativelanguage.dart'
    as gl;

/// Helpers for converting JSON schema maps into Google Gemini [gl.Schema]
/// instances.
class GoogleSchemaHelpers {
  /// Converts a JSON schema map into a [gl.Schema].
  ///
  /// Supports the JSON schema constructs that dartantic emits for tools and
  /// typed output. Throws [ArgumentError] for unsupported constructs such as
  /// `anyOf`, `oneOf`, or union types without `null`.
  static gl.Schema schemaFromJson(Map<String, dynamic> schema) {
    if (schema.containsKey('anyOf') ||
        schema.containsKey('oneOf') ||
        schema.containsKey('allOf')) {
      throw ArgumentError(
        'Gemini does not support anyOf/oneOf/allOf JSON schemas.',
      );
    }

    var nullable = schema['nullable'] as bool? ?? false;
    var rawType = schema['type'];

    if (rawType is List) {
      final types = rawType.cast<dynamic>();
      if (types.contains('null')) {
        nullable = true;
        rawType = types.firstWhere(
          (value) => value != 'null',
          orElse: () => null,
        );
      }
      if (rawType is List) {
        throw ArgumentError('Gemini does not support union schemas: $rawType');
      }
    }

    if (rawType == null) {
      throw ArgumentError("Schema must define a 'type' property: $schema");
    }
    if (rawType is! String) {
      throw ArgumentError('Schema type must be a string: $rawType');
    }

    final description = schema['description'] as String?;
    final format = schema['format'] as String?;
    final enumValues = (schema['enum'] as List?)
        ?.map((value) => value.toString())
        .toList(growable: false);

    switch (rawType) {
      case 'string':
        return gl.Schema(
          type: gl.Type.string,
          description: description ?? '',
          nullable: nullable,
          enum$: enumValues ?? const [],
          format: format ?? '',
        );
      case 'number':
        return gl.Schema(
          type: gl.Type.number,
          description: description ?? '',
          nullable: nullable,
          format: format ?? '',
        );
      case 'integer':
        return gl.Schema(
          type: gl.Type.integer,
          description: description ?? '',
          nullable: nullable,
          format: format ?? '',
        );
      case 'boolean':
        return gl.Schema(
          type: gl.Type.boolean,
          description: description ?? '',
          nullable: nullable,
        );
      case 'array':
        final items = schema['items'];
        if (items is! Map<String, dynamic>) {
          throw ArgumentError('Array schema must define an "items" object.');
        }
        return gl.Schema(
          type: gl.Type.array,
          description: description ?? '',
          nullable: nullable,
          items: schemaFromJson(items),
          maxItems: (schema['maxItems'] as int?) ?? 0,
          minItems: (schema['minItems'] as int?) ?? 0,
        );
      case 'object':
        final rawProperties = schema['properties'];
        final properties = rawProperties != null
            ? Map<String, dynamic>.from(rawProperties as Map)
            : <String, dynamic>{};
        final mappedProperties = properties.map(
          (key, value) => MapEntry(
            key,
            schemaFromJson(Map<String, dynamic>.from(value as Map)),
          ),
        );
        final requiredProps = (schema['required'] as List?)
            ?.map((value) => value.toString())
            .toList(growable: false);
        return gl.Schema(
          type: gl.Type.object,
          description: description ?? '',
          nullable: nullable,
          properties: mappedProperties,
          required: requiredProps ?? const [],
        );
      case 'null':
        return gl.Schema(
          type: gl.Type.string,
          description: description ?? '',
          nullable: true,
        );
      default:
        throw ArgumentError('Unsupported schema type "$rawType".');
    }
  }
}
