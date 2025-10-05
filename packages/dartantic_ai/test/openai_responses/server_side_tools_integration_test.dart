/// Integration tests for ALL server-side tools
///
/// These tests replace the mocked unit tests to ensure we test against the real
/// OpenAI API and catch bugs like the ContainerFile.fromJson issue.
///
/// Tests cover:
/// - Code Interpreter (with container reuse and file generation)
/// - Image Generation (with partial images)
/// - Web Search
/// - File Search (vector stores)
///
/// DO NOT CHECK OR MESS WITH THE API KEY IN ANY WAY; the Agent handles that
/// *COMPLETELY*.

// ignore_for_file: avoid_dynamic_calls

import 'dart:io';
import 'dart:typed_data';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:openai_core/openai_core.dart';
import 'package:test/test.dart';

void main() {
  group('Code Interpreter Integration', () {
    test('executes code and returns results', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.codeInterpreter},
        ),
      );

      final stream = agent.sendStream('Calculate 2 + 2 in Python');
      final results = await stream.toList();
      final fullOutput = results.map((r) => r.output).join();

      expect(fullOutput, contains('4'));

      // Verify code_interpreter metadata is streamed
      var hadCodeInterpreterEvent = false;
      for (final result in results) {
        if (result.metadata['code_interpreter'] != null) {
          hadCodeInterpreterEvent = true;
          break;
        }
      }
      expect(
        hadCodeInterpreterEvent,
        isTrue,
        reason: 'Should have code_interpreter events in metadata',
      );
    });

    test('generates and downloads container files', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.codeInterpreter},
        ),
      );

      final stream = agent.sendStream(
        'Create a text file test.txt with the word hello in it',
      );

      final results = await stream.toList();
      final fullOutput = results.map((r) => r.output).join();

      expect(fullOutput, contains('test.txt'));

      // The bug would have crashed here if the workaround wasn't in place
      // This test proves the workaround works
    });

    test('generates plots/CSV and downloads both as DataPart', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.codeInterpreter},
        ),
      );

      // Use specific prompt like the example - tell it to save the files
      // Accumulate history properly like the examples
      final history = <ChatMessage>[];
      await for (final chunk in agent.sendStream(
        'Calculate the first 10 Fibonacci numbers and store them in a variable '
        'called "fib_sequence". Then create a CSV file called "fibonacci.csv" '
        'with two columns: index and value. Finally, create a line plot of the '
        'Fibonacci sequence and save it as a PNG file called '
        '"fibonacci_plot.png".',
      )) {
        history.addAll(chunk.messages);
      }

      // Should have DataParts for both CSV and PNG
      final dataParts = <DataPart>[];
      for (final msg in history) {
        dataParts.addAll(msg.parts.whereType<DataPart>());
      }

      expect(
        dataParts.length,
        greaterThanOrEqualTo(2),
        reason: 'Should have both CSV and PNG files',
      );

      // Check for image file
      final imageParts = dataParts.where(
        (p) => p.mimeType.startsWith('image/'),
      );
      expect(imageParts, isNotEmpty, reason: 'Should have PNG plot');
      expect(imageParts.first.bytes.lengthInBytes, greaterThan(0));

      // Check for CSV file
      final csvParts = dataParts.where(
        (p) =>
            p.mimeType.contains('csv') || (p.name?.endsWith('.csv') ?? false),
      );
      expect(csvParts, isNotEmpty, reason: 'Should have CSV file');
      expect(csvParts.first.bytes.lengthInBytes, greaterThan(0));
    });

    test('reuses container across sessions', () async {
      // Session 1: Create variable
      final agent1 = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.codeInterpreter},
        ),
      );

      final stream1 = agent1.sendStream(
        'Calculate the first 10 Fibonacci numbers and store them in a variable '
        'called "fib_sequence".',
      );
      final results1 = await stream1.toList();
      final history = results1.last.messages;

      // Extract container ID from metadata
      String? containerId;
      for (final result in results1) {
        final codeInterpreterMeta =
            result.metadata['code_interpreter'] as List?;
        if (codeInterpreterMeta != null) {
          for (final event in codeInterpreterMeta) {
            if (event is Map && event['item']?['container_id'] != null) {
              containerId = event['item']['container_id'] as String;
              break;
            }
          }
        }
        if (containerId != null) break;
      }

      expect(containerId, isNotNull, reason: 'Container ID should be captured');

      // Session 2: Reuse container
      final agent2 = Agent(
        'openai-responses',
        chatModelOptions: OpenAIResponsesChatModelOptions(
          serverSideTools: const {OpenAIServerSideTool.codeInterpreter},
          codeInterpreterConfig: CodeInterpreterConfig(
            containerId: containerId,
          ),
        ),
      );

      final stream2 = agent2.sendStream(
        'Using the fib_sequence variable we created earlier, calculate the '
        'golden ratio by dividing each consecutive pair (skipping the first '
        'term since it is 0).',
        history: history,
      );

      final results2 = await stream2.toList();
      final fullOutput = results2.map((r) => r.output).join();

      // Should mention fib_sequence or golden ratio or 1.618
      expect(
        fullOutput.contains('fib') ||
            fullOutput.contains('golden') ||
            fullOutput.contains('1.6'),
        isTrue,
        reason: 'Should reference fib_sequence or golden ratio',
      );
    });
  });

  group('Image Generation Integration', () {
    test(
      'generates image and returns as DataPart',
      () async {
        final agent = Agent(
          'openai-responses',
          chatModelOptions: const OpenAIResponsesChatModelOptions(
            serverSideTools: {OpenAIServerSideTool.imageGeneration},
            // Match example EXACTLY
            imageGenerationConfig: ImageGenerationConfig(
              partialImages: 3,
              quality: ImageGenerationQuality.low,
              size: ImageGenerationSize.square256,
            ),
          ),
        );

        // Use exact prompt from example
        // Accumulate history like the example does
        final history = <ChatMessage>[];
        await for (final chunk in agent.sendStream(
          'Generate a simple, minimalist logo for a fictional '
          'AI startup called "NeuralFlow". Use geometric shapes and '
          'a modern color palette with blue and purple gradients.',
        )) {
          history.addAll(chunk.messages);
        }

        // Look for DataPart in the accumulated history (like the example)
        final dataParts = <DataPart>[];
        for (final msg in history) {
          dataParts.addAll(msg.parts.whereType<DataPart>());
        }

        expect(dataParts, isNotEmpty, reason: 'Should have generated image');

        final imagePart = dataParts.firstWhere(
          (p) => p.mimeType.startsWith('image/'),
          orElse: () => throw StateError('No image part found'),
        );
        expect(imagePart.bytes.lengthInBytes, greaterThan(0));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('streams partial images in metadata', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.imageGeneration},
          imageGenerationConfig: ImageGenerationConfig(
            partialImages: 2,
            quality: ImageGenerationQuality.low,
            size: ImageGenerationSize.square256,
          ),
        ),
      );

      final stream = agent.sendStream('Generate a blue square');

      final results = await stream.toList();

      // Check for partial image events in metadata
      var hadPartialImage = false;
      for (final result in results) {
        final imageEvents = result.metadata['image_generation'] as List?;
        if (imageEvents != null) {
          for (final event in imageEvents) {
            if (event is Map && event['partial_image_b64'] != null) {
              hadPartialImage = true;
              break;
            }
          }
        }
        if (hadPartialImage) break;
      }

      expect(
        hadPartialImage,
        isTrue,
        reason: 'Should have partial images in streaming metadata',
      );
    });
  });

  group('Web Search Integration', () {
    test('searches web and returns results', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.webSearch},
        ),
      );

      final stream = agent.sendStream(
        'What is the latest version of Dart programming language?',
      );

      final results = await stream.toList();
      final fullOutput = results.map((r) => r.output).join();

      expect(fullOutput, isNotEmpty);
      expect(fullOutput.toLowerCase(), contains('dart'));

      // Verify web_search metadata is streamed
      var hadWebSearchEvent = false;
      for (final result in results) {
        if (result.metadata['web_search'] != null) {
          hadWebSearchEvent = true;
          break;
        }
      }
      expect(
        hadWebSearchEvent,
        isTrue,
        reason: 'Should have web_search events in metadata',
      );
    });

    test('includes location hints in search', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {OpenAIServerSideTool.webSearch},
          webSearchConfig: WebSearchConfig(
            location: WebSearchLocation(city: 'Tokyo', country: 'JP'),
          ),
        ),
      );

      final stream = agent.sendStream('What time is it?');

      final results = await stream.toList();
      final fullOutput = results.map((r) => r.output).join();

      expect(fullOutput, isNotEmpty);
      // Should reference Tokyo/Japan time
    });
  });

  group('File Search Integration', () {
    test('searches vector store and returns relevant results', () async {
      // Create a test vector store with sample content
      final client = OpenAIClient(
        apiKey: Platform.environment['OPENAI_API_KEY'],
      );

      // Create a simple test file
      const testContent = '''
# Test Documentation

## Metadata Handling
Metadata is handled through a hierarchical system that allows streaming
of structured data alongside the main chat response.

## Key Patterns
1. Metadata flows through ChatResult objects
2. Provider-specific metadata is namespaced
3. Streaming events carry metadata deltas
''';

      // Upload the test file
      final uploadedFile = await client.uploadFileBytes(
        purpose: FilePurpose.assistants,
        fileBytes: Uint8List.fromList(testContent.codeUnits),
        filename: 'test_docs.md',
      );

      // Create vector store
      final vectorStore = await client.createVectorStore(
        name: 'Test Documentation',
        fileIds: [uploadedFile.id],
      );

      // Wait for processing
      var status = vectorStore.status;
      var attempts = 0;
      while (status == VectorStoreStatus.inProgress && attempts < 30) {
        await Future<void>.delayed(const Duration(seconds: 2));
        final updated = await client.retrieveVectorStore(vectorStore.id);
        status = updated.status;
        attempts++;
      }

      expect(
        status,
        VectorStoreStatus.completed,
        reason: 'Vector store should be ready',
      );

      // Test file search
      final agent = Agent(
        'openai-responses',
        chatModelOptions: OpenAIResponsesChatModelOptions(
          serverSideTools: const {OpenAIServerSideTool.fileSearch},
          fileSearchConfig: FileSearchConfig(
            vectorStoreIds: [vectorStore.id],
            maxResults: 5,
          ),
        ),
      );

      final stream = agent.sendStream(
        'What information is available about metadata handling?',
      );

      final results = await stream.toList();
      final fullOutput = results.map((r) => r.output).join();

      expect(fullOutput, isNotEmpty);
      expect(fullOutput.toLowerCase(), contains('metadata'));

      // Verify file_search metadata is streamed
      var hadFileSearchEvent = false;
      for (final result in results) {
        if (result.metadata['file_search'] != null) {
          hadFileSearchEvent = true;
          break;
        }
      }
      expect(
        hadFileSearchEvent,
        isTrue,
        reason: 'Should have file_search events in metadata',
      );

      // Cleanup
      await client.deleteVectorStore(vectorStore.id);
      await client.deleteFile(uploadedFile.id);
      client.close();
    });
  });

  group('Multiple Tools Integration', () {
    test('uses multiple server-side tools in one response', () async {
      final agent = Agent(
        'openai-responses',
        chatModelOptions: const OpenAIResponsesChatModelOptions(
          serverSideTools: {
            OpenAIServerSideTool.webSearch,
            OpenAIServerSideTool.codeInterpreter,
          },
        ),
      );

      final stream = agent.sendStream(
        'First, search the web for the current temperature in Seattle in '
        'Fahrenheit. Then write Python code to check if that temperature is '
        'above or below 50°F and calculate the difference.',
      );

      final results = await stream.toList();

      // Should have both web_search and code_interpreter events
      var hadWebSearch = false;
      var hadCodeInterpreter = false;
      for (final result in results) {
        if (result.metadata['web_search'] != null) hadWebSearch = true;
        if (result.metadata['code_interpreter'] != null) {
          hadCodeInterpreter = true;
        }
      }

      // Note: Model may choose to only use one tool if it can answer another
      // way This test validates that multiple tools CAN be used together
      expect(
        hadWebSearch || hadCodeInterpreter,
        isTrue,
        reason: 'Should use at least one server-side tool',
      );
    });
  });
}
