/// Defines capabilities providers can have.
enum ProviderCaps {
  /// Indicates that the provider supports text generation.
  textGeneration,

  /// Indicates that the provider supports embeddings.
  embeddings,

  /// Indicates that the provider supports chat capabilities.
  chat,

  /// Indicates that the provider supports file uploads.
  fileUploads,

  /// Indicates that the provider supports tool calls.
  tools,

  /// Indicates that the provider natively supports structured JSON output.
  structuredOutput;

  /// All available capabilities
  static const Set<ProviderCaps> all = {
    textGeneration,
    embeddings,
    chat,
    fileUploads,
    tools,
    structuredOutput,
  };

  /// Returns all capabilities except those specified in [these].
  static Set<ProviderCaps> allExcept(Set<ProviderCaps> these) =>
      all.difference(these);
}
