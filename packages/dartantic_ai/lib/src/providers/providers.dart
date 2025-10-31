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
  static OpenAIProvider? _openrouter;
  static OpenAIProvider? _together;
  static MistralProvider? _mistral;
  static CohereProvider? _cohere;
  static OpenAIProvider? _googleOpenAI;
  static GoogleProvider? _google;
  static AnthropicProvider? _anthropic;
  static OllamaProvider? _ollama;
  static OpenAIProvider? _ollamaOpenAI;

  /// OpenAI provider (cloud, OpenAI API).
  static OpenAIProvider get openai => _openai ??= OpenAIProvider();

  /// OpenAI Responses provider (Responses API with reasoning metadata).
  static OpenAIResponsesProvider get openaiResponses =>
      _openaiResponses ??= OpenAIResponsesProvider();

  /// OpenRouter provider (OpenAI-compatible, multi-model cloud).
  static OpenAIProvider get openrouter => _openrouter ??= OpenAIProvider(
    name: 'openrouter',
    displayName: 'OpenRouter',
    defaultModelNames: {ModelKind.chat: 'google/gemini-2.5-flash'},
    baseUrl: Uri.parse('https://openrouter.ai/api/v1'),
    apiKeyName: 'OPENROUTER_API_KEY',
    caps: {
      ProviderCaps.chat,
      ProviderCaps.multiToolCalls,
      ProviderCaps.typedOutput,
      ProviderCaps.chatVision,
    },
  );

  /// Together AI provider (OpenAI-compatible, cloud).
  ///
  /// - Note: Tool support is disabled because Together's streaming API returns
  ///   tool calls in a custom format with `<|python_tag|>` prefix instead of
  ///   the standard OpenAI tool_calls format while streaming.
  static OpenAIProvider get together => _together ??= OpenAIProvider(
    name: 'together',
    displayName: 'Together AI',
    defaultModelNames: {
      ModelKind.chat: 'meta-llama/Llama-3.2-3B-Instruct-Turbo',
    },
    baseUrl: Uri.parse('https://api.together.xyz/v1'),
    apiKeyName: 'TOGETHER_API_KEY',
    caps: {ProviderCaps.chat, ProviderCaps.typedOutput},
  );

  /// Mistral AI provider (native API, cloud).
  static MistralProvider get mistral => _mistral ??= MistralProvider();

  /// Cohere provider (OpenAI-compatible, cloud).
  static CohereProvider get cohere => _cohere ??= CohereProvider();

  /// Gemini (OpenAI-compatible) provider (Google AI, OpenAI API).
  static OpenAIProvider get googleOpenAI => _googleOpenAI ??= OpenAIProvider(
    name: 'google-openai',
    displayName: 'Google AI (OpenAI-compatible)',
    defaultModelNames: {
      ModelKind.chat: 'gemini-2.5-flash',
      ModelKind.embeddings: 'text-embedding-004',
    },
    baseUrl: Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/openai',
    ),
    apiKeyName: GoogleProvider.defaultApiKeyName,
    caps: {
      ProviderCaps.chat,
      ProviderCaps.embeddings,
      ProviderCaps.multiToolCalls,
      ProviderCaps.typedOutput,
      ProviderCaps.chatVision,
    },
  );

  /// Google Gemini native provider (uses Gemini API, not OpenAI-compatible).
  static GoogleProvider get google => _google ??= GoogleProvider();

  /// Anthropic provider (Claude, native API).
  static AnthropicProvider get anthropic => _anthropic ??= AnthropicProvider();

  /// Native Ollama provider (local, uses ChatOllama and /api endpoint). No API
  /// key required. Vision models like llava are available.
  static OllamaProvider get ollama => _ollama ??= OllamaProvider();

  /// OpenAI-compatible Ollama provider (local, uses /v1 endpoint). No API key
  /// required. Vision models like llava are available.
  static OpenAIProvider get ollamaOpenAI => _ollamaOpenAI ??= OpenAIProvider(
    name: 'ollama-openai',
    displayName: 'Ollama (OpenAI-compatible)',
    defaultModelNames: {ModelKind.chat: 'llama3.2'},
    baseUrl: Uri.parse('http://localhost:11434/v1'),
    apiKeyName: null,
    caps: {ProviderCaps.chat},
  );

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
    openrouter,
    together,
    mistral,
    cohere,
    google,
    googleOpenAI,
    anthropic,
    ollama,
    ollamaOpenAI,
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
