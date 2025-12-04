// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

void main() async {
  const model = 'gemini';
  final agent = Agent(model);

  final documents = [
    'Python is a programming language',
    'JavaScript is used for web development',
    'The weather is nice today',
    'I enjoy coding in TypeScript',
    'Pizza is my favorite food',
  ];

  print('Embedding ${documents.length} documents...');
  final batchResult = await agent.embedDocuments(documents);
  final embeddings = batchResult.embeddings;

  // Find most similar to a query
  const query = 'programming languages';
  print('\nSearching for documents similar to: "$query"');
  final queryResult = await agent.embedQuery(query);
  final queryEmbedding = queryResult.embeddings;

  // Calculate similarities
  final similarities = <int, double>{};
  for (var i = 0; i < embeddings.length; i++) {
    similarities[i] = EmbeddingsModel.cosineSimilarity(
      queryEmbedding,
      embeddings[i],
    );
  }

  // Sort by similarity
  final sorted = similarities.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  print('\nResults (sorted by similarity):');
  for (final entry in sorted) {
    print(
      '  ${(entry.value * 100).toStringAsFixed(1)}% - '
      '"${documents[entry.key]}"',
    );
  }

  // Custom dimensions example (OpenAI)
  print('\n--- Custom Dimensions (OpenAI) ---');
  final agent2 = Agent(
    model,
    embeddingsModelOptions: const GoogleEmbeddingsModelOptions(
      dimensions: 256, // Reduced dimensions
    ),
  );
  final customResult = await agent2.embedQuery(query);
  final customEmb = customResult.embeddings;
  print('Custom embedding dimensions: ${customEmb.length}');
  print(
    'Standard vs Custom dimension reduction: ${queryEmbedding.length} → '
    '${customEmb.length}',
  );

  exit(0);
}
