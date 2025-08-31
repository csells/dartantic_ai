// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';

Future<void> main() async {
  var totalProviders = 0;
  var totalChatModels = 0;
  var totalEmbeddingModels = 0;
  var totalOtherModels = 0;

  for (final provider in Providers.all) {
    totalProviders++;
    print('\n# ${provider.displayName} (${provider.name})');
    final models = await provider.listModels().toList();
    final modelList = models.toList();

    // Categorize models by type
    final chatModels = modelList
        .where((m) => m.kinds.contains(ModelKind.chat))
        .toList();
    final embeddingModels = modelList
        .where((m) => m.kinds.contains(ModelKind.embeddings))
        .toList();
    final otherModels = modelList
        .where(
          (m) =>
              !m.kinds.contains(ModelKind.chat) &&
              !m.kinds.contains(ModelKind.embeddings),
        )
        .toList();

    totalChatModels += chatModels.length;
    totalEmbeddingModels += embeddingModels.length;
    totalOtherModels += otherModels.length;

    // Print chat models
    if (chatModels.isNotEmpty) {
      print('\n## Chat Models (${chatModels.length})');
      for (final chatModel in chatModels) {
        final model = ModelStringParser(
          provider.name,
          chatModelName: chatModel.name,
        ).toString();
        final kinds = chatModel.kinds.map((k) => k.name).join(', ');
        final displayName = chatModel.displayName != null
            ? '"${chatModel.displayName}"'
            : '';
        print('- $model $displayName ($kinds)');
      }
    }

    // Print embedding models
    if (embeddingModels.isNotEmpty) {
      print('\n## Embedding Models (${embeddingModels.length})');
      for (final embeddingsModel in embeddingModels) {
        final model = ModelStringParser(
          provider.name,
          embeddingsModelName: embeddingsModel.name,
        ).toString();
        final kinds = embeddingsModel.kinds.map((k) => k.name).join(', ');
        final displayName = embeddingsModel.displayName != null
            ? '"${embeddingsModel.displayName}"'
            : '';
        print('- $model $displayName ($kinds)');
      }
    }

    // Print other models
    if (otherModels.isNotEmpty) {
      print('\n## Other Models (${otherModels.length})');
      for (final otherModel in otherModels) {
        final model = ModelStringParser(
          provider.name,
          otherModelName: otherModel.name,
        ).toString();
        final kinds = otherModel.kinds.map((k) => k.name).join(', ');
        final displayName = otherModel.displayName != null
            ? '"${otherModel.displayName}"'
            : '';
        print('- $model $displayName ($kinds)');
      }
    }

    print('\n  Total: ${modelList.length} models');
  }

  print('\n=== Summary ===');
  print('Total providers: $totalProviders');
  print('Total chat models: $totalChatModels');
  print('Total embedding models: $totalEmbeddingModels');
  print('Total other models: $totalOtherModels');
  print(
    'Grand total: '
    '${totalChatModels + totalEmbeddingModels + totalOtherModels} models',
  );
}

// ignore: unused_element
void _printExtra(Map<String, dynamic> extra, {int indent = 0}) {
  final pad = ' ' * indent;
  extra.forEach((key, value) {
    if (value == null) return; // Skip null values
    if (value is Map<String, dynamic>) {
      print('$pad$key:');
      _printExtra(value, indent: indent + 2);
    } else if (value is List) {
      print('$pad$key: [');
      for (final item in value) {
        if (item is Map<String, dynamic>) {
          _printExtra(item, indent: indent + 4);
        } else {
          print('${' ' * (indent + 4)}$item');
        }
      }
      print('$pad]');
    } else {
      print('$pad$key: $value');
    }
  });
  exit(0);
}
