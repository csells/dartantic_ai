// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';

void main() async {
  print('=== Embeddings Example ===\n');

  // Generate embeddings with OpenAI
  print('--- OpenAI Embeddings ---');
  final openaiAgent = Agent('openai');

  const text1 = 'The cat sat on the mat';
  const text2 = 'The kitten rested on the rug';
  const text3 = 'I love programming in Dart';

  print('Generating embeddings for:');
  print('1. "$text1"');
  print('2. "$text2"');
  print('3. "$text3"\n');

  final result1 = await openaiAgent.embedQuery(text1);
  final result2 = await openaiAgent.embedQuery(text2);
  final result3 = await openaiAgent.embedQuery(text3);

  final embedding1 = result1.embeddings;
  final embedding2 = result2.embeddings;
  final embedding3 = result3.embeddings;

  print('Embedding dimensions: ${embedding1.length}');
  print('First 5 values of embedding 1: ${embedding1.take(5).toList()}\n');

  // Calculate similarities
  final sim12 = EmbeddingsModel.cosineSimilarity(embedding1, embedding2);
  final sim13 = EmbeddingsModel.cosineSimilarity(embedding1, embedding3);
  final sim23 = EmbeddingsModel.cosineSimilarity(embedding2, embedding3);

  print('Cosine similarities:');
  print('  Text 1 vs Text 2: ${sim12.toStringAsFixed(4)} (similar sentences)');
  print('  Text 1 vs Text 3: ${sim13.toStringAsFixed(4)} (different topics)');
  print('  Text 2 vs Text 3: ${sim23.toStringAsFixed(4)} (different topics)\n');

  // Batch embeddings with Google
  print('--- Google Batch Embeddings ---');
  final googleAgent = Agent('google');

  final documents = [
    'Python is a programming language',
    'JavaScript is used for web development',
    'The weather is nice today',
    'I enjoy coding in TypeScript',
    'Pizza is my favorite food',
  ];

  print('Embedding ${documents.length} documents...');
  final batchResult = await googleAgent.embedDocuments(documents);
  final embeddings = batchResult.embeddings;

  // Find most similar to a query
  const query = 'programming languages';
  print('\nSearching for documents similar to: "$query"');
  final queryResult = await googleAgent.embedQuery(query);
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

  // Compare embedding providers
  print('\n--- Provider Comparison ---');
  const testText = 'Artificial intelligence is fascinating';

  print('Generating embeddings for: "$testText"\n');

  // OpenAI again
  final openaiResult = await openaiAgent.embedQuery(testText);
  final openaiEmb = openaiResult.embeddings;
  print('OpenAI dimensions: ${openaiEmb.length}');

  // Google
  final googleResult = await googleAgent.embedQuery(testText);
  final googleEmb = googleResult.embeddings;
  print('Google dimensions: ${googleEmb.length}');

  // Mistral
  final mistralAgent = Agent('mistral');
  final mistralResult = await mistralAgent.embedQuery(testText);
  final mistralEmb = mistralResult.embeddings;
  print('Mistral dimensions: ${mistralEmb.length}');

  // Custom dimensions example (OpenAI)
  print('\n--- Custom Dimensions (OpenAI) ---');
  final openaiAgent2 = Agent(
    'openai',
    embeddingsModelOptions: const OpenAIEmbeddingsModelOptions(
      dimensions: 256, // Reduced dimensions
    ),
  );
  final customResult = await openaiAgent2.embedQuery(testText);
  final customEmb = customResult.embeddings;
  print('Custom embedding dimensions: ${customEmb.length}');
  print(
    'Standard vs Custom dimension reduction: ${openaiEmb.length} → '
    '${customEmb.length}',
  );

  exit(0);
}
