// ignore_for_file: avoid_dynamic_calls, unreachable_from_main

import 'dart:io';

import 'package:dartantic_ai/dartantic_ai.dart';

import 'package:example/example.dart';
import 'package:openai_core/openai_core.dart';

void main(List<String> args) async {
  stdout.writeln('🔍 Vector Search Demo');
  stdout.writeln('This demo searches through uploaded documentation files.');
  stdout.writeln();

  // Setup vector store with documentation files
  final vectorStoreId = await setupVectorStore([
    '../../../wiki/Server-Side-Tools-Tech-Design.md',
    '../../../wiki/Message-Handling-Architecture.md',
    '../../../wiki/Streaming-Tool-Call-Architecture.md',
  ]);

  stdout.writeln();
  stdout.writeln('Creating agent with vector store...');

  final agent = Agent(
    'openai-responses',
    chatModelOptions: OpenAIResponsesChatModelOptions(
      serverSideTools: const {OpenAIServerSideTool.fileSearch},
      fileSearchConfig: FileSearchConfig(
        maxResults: 5,
        vectorStoreIds: [vectorStoreId],
      ),
    ),
  );

  const prompt =
      'What are the key architectural patterns for handling metadata '
      'in streaming responses? Include specific examples from the '
      'documentation.';

  stdout.writeln('User: $prompt');
  stdout.write('${agent.displayName}: ');

  final history = <ChatMessage>[];
  await for (final chunk in agent.sendStream(prompt)) {
    stdout.write(chunk.output);
    dumpMetadata(chunk.metadata, prefix: '\n');
    history.addAll(chunk.messages);
  }
  stdout.writeln('');

  dumpMessages(history);
}

/// Sets up a vector store with the specified documentation files.
///
/// This function:
/// 1. Checks if files are already uploaded (by filename)
/// 2. Uploads new files if needed
/// 3. Creates or reuses a cached vector store
/// 4. Returns the vector store ID for use with file search
///
/// The vector store ID is cached in tmp/vector_store_id.txt for reuse
/// across runs to avoid re-uploading files unnecessarily.
Future<String> setupVectorStore(List<String> filePaths) async {
  final client = OpenAIClient(
    apiKey: Platform.environment['OPENAI_API_KEY'],
    // baseUrl: 'https://api.openai.com/v1',
  );

  // Check for cached vector store ID
  final cacheFile = File('tmp/vector_store_id.txt');
  if (cacheFile.existsSync()) {
    final cachedId = await cacheFile.readAsString();
    stdout.writeln('✅ Using cached vector store: $cachedId');
    return cachedId.trim();
  }

  stdout.writeln('📤 Uploading files to OpenAI...');

  // Get list of already uploaded files
  final existingFiles = <String, String>{}; // filename -> file_id
  final filesList = await client.listFiles(purpose: 'assistants');
  for (final file in filesList.data) {
    existingFiles[file.filename] = file.id;
  }

  final fileIds = <String>[];

  // Upload each file (or reuse existing)
  for (final filePath in filePaths) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception(
        'File not found: $filePath\n'
        'Make sure to run this from: packages/dartantic_ai/example\n'
        'Command: dart run bin/server_side_tools/server_side_vector_search.dart',
      );
    }

    final filename = file.uri.pathSegments.last;

    // Check if already uploaded
    if (existingFiles.containsKey(filename)) {
      final existingId = existingFiles[filename]!;
      stdout.writeln('  ♻️  Already uploaded: $filename (ID: $existingId)');
      fileIds.add(existingId);
      continue;
    }

    // Upload new file
    stdout.writeln('  📄 Uploading: $filename');
    final fileBytes = await file.readAsBytes();
    final uploadedFile = await client.uploadFileBytes(
      purpose: FilePurpose.assistants,
      fileBytes: fileBytes,
      filename: filename,
    );

    stdout.writeln('     ✅ Uploaded: ${uploadedFile.id}');
    fileIds.add(uploadedFile.id);
  }

  // Create vector store
  stdout.writeln('🗂️  Creating vector store with ${fileIds.length} files...');
  final vectorStore = await client.createVectorStore(
    name: 'Dartantic Documentation',
    fileIds: fileIds,
    chunkingStrategy: const AutoChunkingStrategy(),
  );

  stdout.writeln('   ✅ Created vector store: ${vectorStore.id}');

  // Wait for vector store to be ready
  stdout.write('   ⏳ Processing files');
  var status = vectorStore.status;
  while (status == VectorStoreStatus.inProgress) {
    stdout.write('.');
    await Future<void>.delayed(const Duration(seconds: 2));
    final updated = await client.retrieveVectorStore(vectorStore.id);
    status = updated.status;
  }
  stdout.writeln(' Done!');

  if (status != VectorStoreStatus.completed) {
    throw Exception('Vector store creation failed with status: $status');
  }

  // Cache the vector store ID
  await cacheFile.create(recursive: true);
  await cacheFile.writeAsString(vectorStore.id);

  return vectorStore.id;
}
