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

  /// The provider's chat models support vision/multi-modal input.
  chatVision,

  /// The provider can stream or return model reasoning ("thinking").
  ///
  /// When supported, thinking text is exposed via ChatResult.metadata under
  /// the key 'thinking'. It is never persisted into message history.
  thinking,
}
