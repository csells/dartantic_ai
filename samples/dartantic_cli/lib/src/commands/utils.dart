import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';

/// Result of parsing an output schema.
class SchemaParseResult {
  SchemaParseResult({this.schema, this.error});

  final JsonSchema? schema;
  final String? error;
}

/// Parse output schema from string (inline JSON or @file reference).
Future<SchemaParseResult> parseOutputSchema(String schemaStr) async {
  String jsonStr;

  // Check if it's a file reference
  if (schemaStr.startsWith('@')) {
    final filePath = schemaStr.substring(1);
    final file = File(filePath);
    if (!await file.exists()) {
      return SchemaParseResult(error: 'Schema file not found: $filePath');
    }
    jsonStr = await file.readAsString();
  } else {
    jsonStr = schemaStr;
  }

  // Parse the JSON
  final schemaMap = jsonDecode(jsonStr) as Map<String, dynamic>;
  return SchemaParseResult(schema: JsonSchema.create(schemaMap));
}

/// Generate a filename based on MIME type.
String generateFilename(String mimeType) {
  final ext = switch (mimeType) {
    'image/png' => 'png',
    'image/jpeg' || 'image/jpg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'application/pdf' => 'pdf',
    'text/csv' => 'csv',
    'text/plain' => 'txt',
    'application/json' => 'json',
    _ => 'bin',
  };
  return 'generated_${DateTime.now().millisecondsSinceEpoch}.$ext';
}
