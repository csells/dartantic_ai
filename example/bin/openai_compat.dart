// ignore_for_file: avoid_print, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

// OpenRouter via OpenAI compatibility
// final provider = Agent.providerFor('openrouter');

// Gemini via OpenAI compatibility
final provider = Agent.providerFor('gemini-compat');

void main() async {
  await textGeneration();
  await embeddings();
  await chat();
  await tools();
  await fileUploads();
  exit(0);
}

Future<void> textGeneration() async {
  print('# Text Generation');
  if (!provider.supports(ProviderCaps.textGeneration)) return;

  final agent = Agent.provider(provider);
  print('## Agent: ${agent.model}');

  final response = await agent.run('Write a haiku about code.');
  print(response.output);
}

Future<void> embeddings() async {
  print('\n# Embeddings');
  if (!provider.supports(ProviderCaps.embeddings)) return;

  final agent = Agent.provider(provider);
  print('## Agent: ${agent.model}');

  final embedding = await agent.createEmbedding('Hello world');
  print('✓ Generated ${embedding.length}-dimensional embedding');
}

Future<void> chat() async {
  print('\n# Chat');
  if (!provider.supports(ProviderCaps.chat)) return;

  final agent = Agent.provider(provider);
  print('## Agent: ${agent.model}');

  var messages = <Message>[];
  var response = await agent.run('My name is Alice', messages: messages);
  print('User: My name is Alice');
  print('AI: ${response.output}');

  messages = response.messages.toList();
  response = await agent.run('What is my name?', messages: messages);
  print('User: What is my name?');
  print('AI: ${response.output}');
}

Future<void> tools() async {
  print('\n# Tools');
  if (!provider.supports(ProviderCaps.tools)) return;

  final agent = Agent.provider(
    provider,
    tools: [
      Tool(
        name: 'get_time',
        description: 'Get current time',
        inputSchema: {'type': 'object', 'properties': {}}.toSchema(),
        onCall: (input) async => {'time': DateTime.now().toString()},
      ),
    ],
  );
  print('## Agent: ${agent.model}');

  final response = await agent.run('What time is it?');
  print(response.output);
}

Future<void> fileUploads() async {
  print('\n# File Uploads');

  if (!provider.supports(ProviderCaps.fileUploads)) return;

  final agent = Agent.provider(provider);
  print('## Agent: ${agent.model}');

  final file = File('bin/files/bio.txt');
  final response = await agent.run(
    'Can you summarize this file for me?',
    attachments: [await DataPart.stream(file.openRead(), name: file.path)],
  );
  print(response.output);
}

extension on Provider {
  bool supports(ProviderCaps cap) {
    final supports = provider.caps.contains(cap);
    if (!supports) print('❌ ${provider.name} does NOT support ${cap.name}');
    return supports;
  }
}
