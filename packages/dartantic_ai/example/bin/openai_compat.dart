// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

/// Demonstrates OpenAI-compatible providers in dartantic.
///
/// This example shows:
/// 1. How to define and register a custom OpenAI-compatible provider
/// 2. How to use built-in OpenAI-compatible providers
/// 3. Multi-provider conversation with OpenAI-compatible APIs
void main() async {
  // --- Part 1: Custom OpenAI-Compatible Provider ---
  print('=== Part 1: Custom OpenAI-Compatible Provider (Fireworks) ===\n');

  // You can define your own OpenAI-compatible provider
  final fireworks = OpenAIProvider(
    name: 'fireworks',
    displayName: 'Fireworks',
    defaultModelNames: {
      ModelKind.chat: 'accounts/fireworks/models/llama-v3p1-8b-instruct',
    },
    baseUrl: Uri.parse('https://api.fireworks.ai/inference/v1'),
    apiKeyName: 'FIREWORKS_API_KEY',
  );

  // Register it like any other provider
  Providers.providerMap['fireworks'] = fireworks;

  // Use it like any other provider
  if (Platform.environment.containsKey('FIREWORKS_API_KEY')) {
    final agent = Agent('fireworks');
    print('${agent.displayName}: Sending question...');
    final result = await agent.send(
      'What is the meaning of life? (one sentence)',
      history: [ChatMessage.system('Be concise.')],
    );
    print('${agent.displayName}: ${result.output}\n');
  } else {
    print('Skipping Fireworks (no FIREWORKS_API_KEY set)\n');
  }

  // --- Part 2: Built-in OpenAI-Compatible Providers ---
  print('=== Part 2: Built-in OpenAI-Compatible Providers ===\n');

  // These providers are pre-registered and ready to use:
  // - openrouter: OpenRouter (aggregates many models)
  // - together: Together AI
  // - cohere: Cohere (via OpenAI compatibility layer)
  // - google-openai: Google AI (via OpenAI compatibility layer)
  // - ollama-openai: Ollama (local models via OpenAI API)

  final builtInProviders = [
    ('openrouter', 'OPENROUTER_API_KEY'),
    ('together', 'TOGETHER_API_KEY'),
    ('cohere', 'COHERE_API_KEY'),
    ('google-openai', 'GOOGLE_API_KEY'),
    ('ollama-openai', null), // Ollama doesn't require an API key
  ];

  for (final (providerName, apiKeyName) in builtInProviders) {
    final hasKey =
        apiKeyName == null || Platform.environment.containsKey(apiKeyName);

    if (hasKey) {
      final provider = Providers.get(providerName);
      print('✓ $providerName is available (${provider.displayName})');
    } else {
      print('○ $providerName (no $apiKeyName set)');
    }
  }

  // --- Part 3: Multi-Provider Conversation ---
  print('\n=== Part 3: Multi-Provider Conversation ===\n');

  // Find available providers for the conversation demo
  final availableProviders = <String>[];
  for (final (providerName, apiKeyName) in builtInProviders) {
    if (apiKeyName == null || Platform.environment.containsKey(apiKeyName)) {
      availableProviders.add(providerName);
    }
  }

  if (availableProviders.length >= 2) {
    final history = <ChatMessage>[];

    // First provider introduces itself
    final firstProvider = availableProviders[0];
    final agent1 = Agent(firstProvider);
    print('## Starting with ${agent1.displayName}');
    final result1 = await agent1.send(
      'Introduce yourself briefly (1-2 sentences).',
    );
    history.addAll(result1.messages);
    print('${agent1.displayName}: ${result1.output}\n');

    // Second provider continues
    final secondProvider = availableProviders[1];
    final agent2 = Agent(secondProvider);
    print('## Switching to ${agent2.displayName}');
    final result2 = await agent2.send(
      'Based on the previous message, what provider introduced itself?',
      history: history,
    );
    history.addAll(result2.messages);
    print('${agent2.displayName}: ${result2.output}\n');

    print('## Provider sequence:');
    print('  → ${agent1.displayName}');
    print('  → ${agent2.displayName}');
  } else {
    print(
      'Need at least 2 providers with API keys for conversation demo.\n'
      'Set API keys for: OPENROUTER_API_KEY, TOGETHER_API_KEY, etc.',
    );
  }

  exit(0);
}
