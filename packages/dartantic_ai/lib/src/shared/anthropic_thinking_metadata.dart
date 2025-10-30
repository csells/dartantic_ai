/// Metadata helpers for Anthropic thinking blocks.
///
/// When thinking is enabled and tool calls are present, Anthropic requires
/// the complete ThinkingBlock (including signature) to be preserved in
/// conversation history. This helper stores the thinking block data in
/// message metadata so it can be reconstructed when sending history back.
class AnthropicThinkingMetadata {
  AnthropicThinkingMetadata._();

  /// Metadata key used to store thinking block data on chat messages.
  static const thinkingBlockKey = '_anthropic_thinking_block';

  /// Key for thinking text within the stored block data.
  static const thinkingTextKey = 'thinking';

  /// Key for signature within the stored block data.
  static const signatureKey = 'signature';

  /// Extracts stored thinking block data from a chat message metadata map.
  static Map<String, Object?>? getThinkingBlock(
    Map<String, Object?>? metadata,
  ) {
    if (metadata == null) return null;
    final value = metadata[thinkingBlockKey];
    if (value is Map<String, Object?>) return value;
    return null;
  }

  /// Creates a serializable thinking block data map from the provided fields.
  static Map<String, Object?> buildThinkingBlock({
    required String thinking,
    String? signature,
  }) =>
      {
        thinkingTextKey: thinking,
        if (signature != null) signatureKey: signature,
      };

  /// Reads the thinking text from stored block data.
  static String? thinkingText(Map<String, Object?>? blockData) =>
      blockData?[thinkingTextKey] as String?;

  /// Reads the signature from stored block data.
  static String? signature(Map<String, Object?>? blockData) =>
      blockData?[signatureKey] as String?;
}
