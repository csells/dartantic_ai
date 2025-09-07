/// Capabilities of a chat provider.
enum ProviderCaps {
  /// The provider supports chat.
  chat,

  /// The provider supports embeddings.
  embeddings,

  /// The provider supports multiple tool calls.
  multiToolCalls,

  /// The provider supports typed output.
  typedOutput,

  /// The provider supports typed output with tool calls simultaneously.
  /// This includes providers that use return_result pattern (Anthropic) or
  /// native response_format (OpenAI).
  typedOutputWithTools,

  /// The provider supports vision/multi-modal input (images, etc.).
  vision,

  /// The provider can stream or return model reasoning ("thinking").
  ///
  /// When supported, thinking text is exposed via `ChatResult.metadata`
  /// under the key 'thinking' during streaming. On consolidation, the
  /// full thinking string for that assistant turn is attached to the
  /// associated `ChatMessage.metadata['thinking']`. Thinking is never
  /// included as visible content parts and is never sent back to providers
  /// via history.
  thinking,

  /// The provider supports enabling server-side tools exposed by the API.
  serverSideTools,

  /// The provider supports session-based prompt caching.
  promptCaching,
}
