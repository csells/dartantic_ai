import 'package:dartantic_interface/dartantic_interface.dart';

import 'anthropic_provider.dart';
import 'cohere_provider.dart';
import 'google_provider.dart';
import 'mistral_provider.dart';
import 'ollama_provider.dart';
import 'openai_provider.dart';
import 'openai_responses_provider.dart';

export 'anthropic_provider.dart';
export 'cohere_provider.dart';
export 'google_provider.dart';
export 'mistral_provider.dart';
export 'ollama_provider.dart';
export 'openai_provider.dart';
export 'openai_responses_provider.dart';

/// Providers for built-in chat and embeddings models.
class Providers {
  Providers._();

  // Private cache fields for lazy initialization
  static OpenAIProvider? _openai;
  static OpenAIResponsesProvider? _openaiResponses;
  static MistralProvider? _mistral;
  static CohereProvider? _cohere;
  static GoogleProvider? _google;
  static AnthropicProvider? _anthropic;
  static OllamaProvider? _ollama;

  /// OpenAI provider (cloud, OpenAI API).
  static OpenAIProvider get openai => _openai ??= OpenAIProvider();

  /// OpenAI Responses provider (Responses API with reasoning metadata).
  static OpenAIResponsesProvider get openaiResponses =>
      _openaiResponses ??= OpenAIResponsesProvider();

  /// Mistral AI provider (native API, cloud).
  static MistralProvider get mistral => _mistral ??= MistralProvider();

  /// Cohere provider (OpenAI-compatible, cloud).
  static CohereProvider get cohere => _cohere ??= CohereProvider();

  /// Google Gemini native provider (uses Gemini API, not OpenAI-compatible).
  static GoogleProvider get google => _google ??= GoogleProvider();

  /// Anthropic provider (Claude, native API).
  static AnthropicProvider get anthropic => _anthropic ??= AnthropicProvider();

  /// Native Ollama provider (local, uses ChatOllama and /api endpoint). No API
  /// key required. Vision models like llava are available.
  static OllamaProvider get ollama => _ollama ??= OllamaProvider();

  /// Returns a list of all available providers (static fields above).
  ///
  /// Use this to iterate or display all providers in a UI.
  /// NOTE: Filters out duplicate providers by alias.
  static List<Provider> get all => providerMap.entries
      .where((e) => !e.value.aliases.contains(e.key))
      .map((e) => e.value)
      .toList();

  /// Returns all providers that have the specified capabilities.
  static List<Provider> allWith(Set<ProviderCaps> caps) =>
      all.where((p) => p.caps.containsAll(caps)).toList();

  static final _providerMap = <String, Provider>{};

  /// Returns all intrinsic providers (lazily evaluated).
  static List<Provider> get _intrinsicProviders => <Provider>[
    openai,
    openaiResponses,
    mistral,
    cohere,
    google,
    anthropic,
    ollama,
  ];

  /// Returns a map of all providers by name or alias.
  /// Extensible at runtime by adding to your own [Provider] subclass.
  static Map<String, Provider> get providerMap {
    if (_providerMap.isEmpty) {
      for (final provider in _intrinsicProviders) {
        final providerName = provider.name.toLowerCase();
        final existingProvider = _providerMap[providerName];
        if (existingProvider != null &&
            !identical(existingProvider, provider)) {
          throw StateError(
            'Provider name "$providerName" is already registered by '
            '"${existingProvider.name}".',
          );
        }
        _providerMap[providerName] = provider;
        for (final alias in provider.aliases) {
          final providerAlias = alias.toLowerCase();
          final existingAliasProvider = _providerMap[providerAlias];
          if (existingAliasProvider != null &&
              !identical(existingAliasProvider, provider)) {
            throw StateError(
              'Provider alias "$providerAlias" is already registered by '
              '"${existingAliasProvider.name}".',
            );
          }
          _providerMap[providerAlias] = provider;
        }
      }
    }

    return _providerMap;
  }

  /// Looks up a provider by name or alias (case-insensitive). Throws if not
  /// found.
  static Provider get(String name) {
    final providerName = name.toLowerCase();
    final provider = providerMap[providerName];
    if (provider == null) throw Exception('Provider $providerName not found');
    return provider;
  }
}
