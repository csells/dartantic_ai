import 'package:openai_core/openai_core.dart' as openai;

/// Metadata helpers for the OpenAI Responses provider.
class OpenAIResponsesMetadata {
  OpenAIResponsesMetadata._();

  /// Metadata key used to store session state on chat messages.
  static const sessionKey = '_responses_session';

  /// Key for `previousResponseId` persisted in session metadata.
  static const previousResponseIdKey = 'previous_response_id';

  /// Key for pending items persisted in session metadata.
  static const pendingItemsKey = 'pending';

  /// Extracts stored session data from a chat message metadata map.
  static Map<String, Object?>? getSessionData(Map<String, Object?>? metadata) {
    if (metadata == null) return null;
    final value = metadata[sessionKey];
    if (value is Map<String, Object?>) return value;
    return null;
  }

  /// Stores session data back onto a chat message metadata map.
  static void setSessionData(
    Map<String, Object?> metadata,
    Map<String, Object?> session,
  ) {
    metadata[sessionKey] = session;
  }

  /// Removes persisted session metadata from the provided map.
  static void clearSessionData(Map<String, Object?> metadata) {
    metadata.remove(sessionKey);
  }

  /// Creates a serialisable session map from the provided fields.
  static Map<String, Object?> buildSession({
    required String? previousResponseId,
    Iterable<openai.ResponseItem>? pending,
  }) => {
    if (previousResponseId != null) previousResponseIdKey: previousResponseId,
    if (pending != null)
      pendingItemsKey: pending
          .map((item) => item.toJson())
          .toList(growable: false),
  };

  /// Reads the stored previous response identifier from [session].
  static String? previousResponseId(Map<String, Object?>? session) =>
      session?[previousResponseIdKey] as String?;

  /// Reads any stored pending [openai.ResponseItem] JSON payloads from
  /// [session].
  static List<openai.ResponseItem> pendingItems(Map<String, Object?>? session) {
    if (session == null) return const [];
    final raw = session[pendingItemsKey];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(openai.ResponseItem.fromJson)
          .toList(growable: false);
    }
    return const [];
  }
}
