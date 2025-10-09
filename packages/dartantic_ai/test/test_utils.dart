import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';

/// Validates that a message history follows the correct conversation structure:
/// 1. At most one system message, which must be first if present
/// 2. After any system message, messages must alternate user/model/user/model
///
/// Throws an [AssertionError] if the message history is invalid.
void validateMessageHistory(List<ChatMessage> messages) {
  if (messages.isEmpty) return;

  var index = 0;

  // Check for system message (must be first if present)
  if (messages[index].role == ChatMessageRole.system) {
    index++;
    // Check for duplicate system messages
    for (var i = index; i < messages.length; i++) {
      if (messages[i].role == ChatMessageRole.system) {
        throw AssertionError(
          'Found system message at index $i, but system messages can only '
          'appear at index 0. Message: ${messages[i]}',
        );
      }
    }
  }

  // Check user/model alternation
  if (index < messages.length) {
    // First non-system message must be from user
    if (messages[index].role != ChatMessageRole.user) {
      throw AssertionError(
        'First non-system message must be from user, but found '
        '${messages[index].role} at index $index. Message: ${messages[index]}',
      );
    }

    // Check alternation pattern
    var expectingUser = true;
    for (var i = index; i < messages.length; i++) {
      final expectedRole = expectingUser
          ? ChatMessageRole.user
          : ChatMessageRole.model;
      if (messages[i].role != expectedRole) {
        throw AssertionError(
          'Expected ${expectedRole.name} message at index $i, but found '
          '${messages[i].role.name}. Messages must alternate user/model. '
          'Message: ${messages[i]}',
        );
      }
      expectingUser = !expectingUser;
    }
  }
}

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
