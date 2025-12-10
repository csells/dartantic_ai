import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

/// Capabilities of a provider's default model for testing purposes.
///
/// This enum is test-only and describes what capabilities the default model
/// of each provider supports. It is NOT part of the public API.
enum ProviderTestCaps {
  /// The provider supports chat.
  chat,

  /// The provider supports embeddings.
  embeddings,

  /// The provider supports multiple tool calls.
  multiToolCalls,

  /// The provider supports typed output.
  typedOutput,

  /// The provider supports typed output with tool calls simultaneously.
  typedOutputWithTools,

  /// The provider's chat models support vision/multi-modal input.
  chatVision,

  /// The provider can generate media assets (images, audio, documents, etc.).
  mediaGeneration,

  /// The provider can stream or return model reasoning ("thinking").
  thinking,
}

/// Test-only mapping of provider names to the capabilities of their default
/// models.
const providerTestCaps = <String, Set<ProviderTestCaps>>{
  'openai': {
    ProviderTestCaps.chat,
    ProviderTestCaps.embeddings,
    ProviderTestCaps.multiToolCalls,
    ProviderTestCaps.typedOutput,
    ProviderTestCaps.typedOutputWithTools,
    ProviderTestCaps.chatVision,
  },
  'openai-responses': {
    ProviderTestCaps.chat,
    ProviderTestCaps.embeddings,
    ProviderTestCaps.multiToolCalls,
    ProviderTestCaps.typedOutput,
    ProviderTestCaps.typedOutputWithTools,
    ProviderTestCaps.thinking,
    ProviderTestCaps.chatVision,
    ProviderTestCaps.mediaGeneration,
  },
  'anthropic': {
    ProviderTestCaps.chat,
    ProviderTestCaps.multiToolCalls,
    ProviderTestCaps.typedOutput,
    ProviderTestCaps.typedOutputWithTools,
    ProviderTestCaps.chatVision,
    ProviderTestCaps.thinking,
    ProviderTestCaps.mediaGeneration,
  },
  'google': {
    ProviderTestCaps.chat,
    ProviderTestCaps.embeddings,
    ProviderTestCaps.multiToolCalls,
    ProviderTestCaps.typedOutput,
    ProviderTestCaps.typedOutputWithTools,
    ProviderTestCaps.chatVision,
    ProviderTestCaps.thinking,
    ProviderTestCaps.mediaGeneration,
  },
  'mistral': {ProviderTestCaps.chat, ProviderTestCaps.embeddings},
  'cohere': {
    ProviderTestCaps.chat,
    ProviderTestCaps.embeddings,
    // Note: multiToolCalls disabled due to Cohere API bug with non-unique
    // tool IDs
    ProviderTestCaps.typedOutput,
  },
  'ollama': {ProviderTestCaps.chat, ProviderTestCaps.typedOutput},
  'openrouter': {
    ProviderTestCaps.chat,
    // Note: OpenRouter does not have a default embeddings model
    ProviderTestCaps.multiToolCalls,
    ProviderTestCaps.typedOutput,
    ProviderTestCaps.typedOutputWithTools,
    ProviderTestCaps.chatVision,
    ProviderTestCaps.thinking,
    // Note: OpenRouter does not support media generation
  },
};

/// Returns the test capabilities for the given provider name, or an empty set
/// if the provider is not in the mapping.
Set<ProviderTestCaps> getProviderTestCaps(String providerName) =>
    providerTestCaps[providerName] ?? const {};

/// Returns true if the provider has all the required capabilities for testing.
bool providerHasTestCaps(
  String providerName,
  Set<ProviderTestCaps> requiredCaps,
) {
  final caps = getProviderTestCaps(providerName);
  return requiredCaps.every(caps.contains);
}

/// Runs a parameterized test across every provider selected by the filters.
void runProviderTest(
  String description,
  Future<void> Function(Provider provider) testFunction, {
  Set<ProviderTestCaps>? requiredCaps,
  bool edgeCase = false,
  Timeout? timeout,
  Set<String>? skipProviders,
  String Function(Provider provider, String defaultLabel)? labelBuilder,
}) {
  final normalizedSkips =
      skipProviders?.map((name) => name.toLowerCase()).toSet() ?? const {};

  final providerEntries = edgeCase
      ? <({Provider provider, String defaultLabel})>[
          (
            provider: Agent.getProvider('google'),
            defaultLabel: 'google:gemini-2.5-flash',
          ),
        ]
      : Agent.allProviders
            .where(
              (p) =>
                  requiredCaps == null ||
                  providerHasTestCaps(p.name, requiredCaps),
            )
            .map(
              (p) => (
                provider: p,
                defaultLabel:
                    '${p.name}:${p.defaultModelNames[ModelKind.chat]}',
              ),
            );

  for (final entry in providerEntries) {
    final provider = entry.provider;
    final providerName = provider.name.toLowerCase();
    final isSkipped = normalizedSkips.contains(providerName);
    final label =
        labelBuilder?.call(provider, entry.defaultLabel) ?? entry.defaultLabel;

    test(
      '$label: $description',
      () async {
        await testFunction(provider);
      },
      timeout: timeout,
      skip: isSkipped,
    );
  }
}
