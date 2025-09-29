/// Metadata helpers for the OpenAI Responses provider.
class OpenAIResponsesMetadata {
  OpenAIResponsesMetadata._();

  /// Metadata key used to store session state on chat messages.
  static const sessionKey = '_responses_session';

  /// Key for `responseId` persisted in session metadata.
  static const responseIdKey = 'response_id';

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
  static Map<String, Object?> buildSession({required String? responseId}) => {
    if (responseId != null) responseIdKey: responseId,
  };

  /// Reads the stored response identifier from [session].
  static String? responseId(Map<String, Object?>? session) =>
      session?[responseIdKey] as String?;
}
