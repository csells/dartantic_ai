import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';

/// Validates that metadata is not duplicated across streaming results.
///
/// Checks that each metadata key+value pair appears at most once during
/// streaming. This ensures the orchestrator doesn't re-yield metadata that
/// was already streamed.
///
/// Throws an [AssertionError] if duplicate metadata is found.
void validateNoMetadataDuplicates(List<ChatResult> results) {
  final seenMetadata = <String, Set<String>>{};

  for (var i = 0; i < results.length; i++) {
    final metadata = results[i].metadata;
    if (metadata.isEmpty) continue;

    for (final entry in metadata.entries) {
      final key = entry.key;
      final valueJson = jsonEncode(entry.value);

      // Initialize set for this key if not seen before
      seenMetadata[key] ??= <String>{};

      // Check if we've seen this exact key+value before
      if (seenMetadata[key]!.contains(valueJson)) {
        throw AssertionError(
          'Duplicate metadata found at result index $i:\n'
          '  Key: "$key"\n'
          '  Value: $valueJson\n'
          'This metadata was already yielded in a previous result. '
          'Each metadata item should only be yielded once during streaming.',
        );
      }

      // Mark this key+value as seen
      seenMetadata[key]!.add(valueJson);
    }
  }
}
