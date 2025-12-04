/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'dart:io';
import 'dart:typed_data';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:test/test.dart';

import 'test_helpers/run_provider_test.dart';

void main() {
  late Uint8List testImageBytes;
  late Uint8List testTextBytes;
  late Uint8List testPdfBytes;

  setUpAll(() async {
    // Load test files once for all tests
    testImageBytes = await File('test/files/pikachu.png').readAsBytes();
    testTextBytes = await File('test/files/bio.txt').readAsBytes();
    testPdfBytes = await File('test/files/Tiny PDF.pdf').readAsBytes();
  });

  // Helper to get vision-capable model name for vision-only providers
  String getVisionModelName(Provider provider) => switch (provider.name) {
    'together' => 'Qwen/Qwen2.5-VL-72B-Instruct',
    'ollama' => 'llava:7b',
    'ollama-openai' => 'llava:7b',
    'cohere' => 'c4ai-aya-vision-8b',
    _ => provider.defaultModelNames[ModelKind.chat] ?? '',
  };

  // Helper to run tests on general-purpose providers
  void runGeneralPurposeTest(
    String description,
    Future<void> Function(Provider provider, Agent agent) testFunction, {
    bool edgeCase = false,
  }) {
    runProviderTest(
      description,
      (provider) async {
        final defaultModel = provider.defaultModelNames[ModelKind.chat];
        expect(
          defaultModel,
          isNotNull,
          reason:
              'Provider ${provider.name} should expose a default '
              'chat model for multi-modal usage',
        );
        expect(
          defaultModel!.isNotEmpty,
          isTrue,
          reason:
              'Provider ${provider.name} default chat model '
              'should not be empty',
        );

        final agent = Agent(provider.name);
        await testFunction(provider, agent);
      },
      requiredCaps: {ProviderCaps.chatVision},
      edgeCase: edgeCase,
    );
  }

  // Helper to run tests on vision providers
  void runVisionOnlyTest(
    String description,
    Future<void> Function(Provider provider, Agent agent) testFunction,
  ) {
    runProviderTest(description, (provider) async {
      final modelName = getVisionModelName(provider);
      expect(
        modelName.isNotEmpty,
        isTrue,
        reason:
            'Provider ${provider.name} should supply a '
            'vision-capable model name',
      );

      final agent = Agent('${provider.name}:$modelName');
      await testFunction(provider, agent);
    }, requiredCaps: {ProviderCaps.chatVision});
  }

  group('Multi-Modal', () {
    group('General-purpose multi-modal (images + text + PDFs)', () {
      runGeneralPurposeTest('handles single image attachment', (
        provider,
        agent,
      ) async {
        // Use the pre-loaded test image
        final imageData = testImageBytes;

        final result = await agent.send(
          'Describe this image in one word',
          attachments: [DataPart(imageData, mimeType: 'image/png')],
        );

        expect(result.output, isNotEmpty);
        // Verify the message has the attachment
        final userMessage = result.messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMessage.parts.whereType<DataPart>().length, equals(1));
      });

      runGeneralPurposeTest('handles multiple images', (provider, agent) async {
        // Use pre-loaded test images
        final image1 = testImageBytes;
        final image2 = testImageBytes;

        final result = await agent.send(
          'How many images do you see?',
          attachments: [
            DataPart(image1, mimeType: 'image/png'),
            DataPart(image2, mimeType: 'image/png'),
          ],
        );

        expect(result.output, isNotEmpty);
        // Verify both attachments are in the message
        final userMessage = result.messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMessage.parts.whereType<DataPart>().length, equals(2));
      });

      runGeneralPurposeTest('handles text with image', (provider, agent) async {
        final imageData = testImageBytes;

        final result = await agent.send(
          'What type of file is this?',
          attachments: [DataPart(imageData, mimeType: 'image/png')],
        );

        expect(result.output, isNotEmpty);
        // Should have both text and image parts
        final userMessage = result.messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMessage.parts.whereType<TextPart>().length, equals(1));
        expect(userMessage.parts.whereType<DataPart>().length, equals(1));
      });

      runGeneralPurposeTest('handles text file attachment', (
        provider,
        agent,
      ) async {
        final result = await agent.send(
          'Summarize this text file',
          attachments: [DataPart(testTextBytes, mimeType: 'text/plain')],
        );

        expect(result.output, isNotEmpty);
        // Verify the message has the attachment
        final userMessage = result.messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMessage.parts.whereType<DataPart>().length, equals(1));
      });

      runGeneralPurposeTest('handles PDF file attachment', (
        provider,
        agent,
      ) async {
        // Skip for OpenAI-compatible providers as they don't support PDF
        // attachments natively and sending as base64 text is too
        // large/inefficient
        if (provider.name.contains('openai') ||
            provider.name == 'cohere' ||
            provider.name == 'ollama') {
          return;
        }

        final result = await agent.send(
          'What does this PDF contain?',
          attachments: [DataPart(testPdfBytes, mimeType: 'application/pdf')],
        );

        expect(result.output, isNotEmpty);
        // Verify the message has the attachment
        final userMessage = result.messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMessage.parts.whereType<DataPart>().length, equals(1));
      });

      runGeneralPurposeTest('handles mixed file types', (
        provider,
        agent,
      ) async {
        final result = await agent.send(
          'Compare the image and text content',
          attachments: [
            DataPart(testImageBytes, mimeType: 'image/png'),
            DataPart(testTextBytes, mimeType: 'text/plain'),
          ],
        );

        expect(result.output, isNotEmpty);
        // Verify both attachments are in the message
        final userMessage = result.messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMessage.parts.whereType<DataPart>().length, equals(2));
      });

      runProviderTest(
        'handles single URL attachment',
        (provider) async {
          final agent = Agent(provider.name);
          final result = await agent.send(
            'What is in this image?',
            attachments: [
              LinkPart(
                Uri.parse(
                  'https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png',
                ),
              ),
            ],
          );

          expect(result.output, isNotEmpty);
          // Verify the link is in the message
          final userMessage = result.messages.firstWhere(
            (m) => m.role == ChatMessageRole.user,
          );
          expect(userMessage.parts.whereType<LinkPart>().length, equals(1));
        },
        requiredCaps: {ProviderCaps.chatVision},
        // Google requires File API upload, not arbitrary URLs
        // Ollama/Local doesn't support external URLs
        // Together might support it but let's be safe
        skipProviders: {
          'google',
          'google-openai',
          'ollama',
          'ollama-openai',
          'together',
          'mistral',
          'cohere', // No vision anyway
        },
      );

      runProviderTest(
        'handles multiple URLs',
        (provider) async {
          final agent = Agent(provider.name);
          final result = await agent.send(
            'Are these images the same?',
            attachments: [
              LinkPart(
                Uri.parse(
                  'https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png',
                ),
              ),
              LinkPart(
                Uri.parse(
                  'https://www.google.com/images/branding/googlelogo/2x/googlelogo_color_272x92dp.png',
                ),
              ),
            ],
          );

          expect(result.output, isNotEmpty);
          // Verify both links are in the message
          final userMessage = result.messages.firstWhere(
            (m) => m.role == ChatMessageRole.user,
          );
          expect(userMessage.parts.whereType<LinkPart>().length, equals(2));
        },
        requiredCaps: {ProviderCaps.chatVision},
        skipProviders: {
          'google',
          'google-openai',
          'ollama',
          'ollama-openai',
          'together',
          'mistral',
          'cohere',
        },
      );
    });

    group('Vision-only multi-modal (images only)', () {
      runVisionOnlyTest('handles single image attachment', (
        provider,
        agent,
      ) async {
        // Debug: verify correct model is being used
        if (provider.name == 'together') {
          expect(agent.model, contains('Qwen/Qwen2.5-VL-72B-Instruct'));
        }

        // Use the pre-loaded test image
        final imageData = testImageBytes;

        final result = await agent.send(
          'Describe this image in one word',
          attachments: [DataPart(imageData, mimeType: 'image/png')],
        );

        expect(result.output, isNotEmpty);
        // Verify the message has the attachment
        final userMessage = result.messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMessage.parts.whereType<DataPart>().length, equals(1));
      });

      runVisionOnlyTest('handles multiple images', (provider, agent) async {
        // Use pre-loaded test images
        final image1 = testImageBytes;
        final image2 = testImageBytes;

        final result = await agent.send(
          'How many images do you see?',
          attachments: [
            DataPart(image1, mimeType: 'image/png'),
            DataPart(image2, mimeType: 'image/png'),
          ],
        );

        expect(result.output, isNotEmpty);
        // Verify both attachments are in the message
        final userMessage = result.messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMessage.parts.whereType<DataPart>().length, equals(2));
      });

      runVisionOnlyTest('handles text with image', (provider, agent) async {
        final imageData = testImageBytes;

        final result = await agent.send(
          'What type of file is this?',
          attachments: [DataPart(imageData, mimeType: 'image/png')],
        );

        expect(result.output, isNotEmpty);
        // Should have both text and image parts
        final userMessage = result.messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMessage.parts.whereType<TextPart>().length, equals(1));
        expect(userMessage.parts.whereType<DataPart>().length, equals(1));
      });
    });

    group('edge cases (Google only)', () {
      runGeneralPurposeTest('handles empty attachments list', (
        provider,
        agent,
      ) async {
        final result = await agent.send(
          'Hello',
          attachments: [], // Empty attachments
        );

        expect(result.output, isNotEmpty);
        // Should just have text part
        final userMessage = result.messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMessage.parts.whereType<TextPart>().length, equals(1));
        expect(userMessage.parts.whereType<DataPart>().length, equals(0));
      }, edgeCase: true);

      runGeneralPurposeTest('handles very large images', (
        provider,
        agent,
      ) async {
        // Use the pikachu image as our "large" image for this test
        final largeImage = testImageBytes;

        final result = await agent.send(
          'Can you process this large image?',
          attachments: [DataPart(largeImage, mimeType: 'image/png')],
        );

        expect(result.output, isNotEmpty);
      }, edgeCase: true);

      runGeneralPurposeTest('handles unusual MIME types', (
        provider,
        agent,
      ) async {
        // Use the pikachu image for this test too
        final data = testImageBytes;

        final result = await agent.send(
          'What format is this?',
          attachments: [DataPart(data, mimeType: 'image/png')],
        );

        expect(result.output, isNotEmpty);
      }, edgeCase: true);

      runGeneralPurposeTest('handles attachment without text', (
        provider,
        agent,
      ) async {
        final imageData = testImageBytes;

        final result = await agent.send(
          '', // Empty text
          attachments: [DataPart(imageData, mimeType: 'image/png')],
        );

        expect(result.output, isNotEmpty);
      }, edgeCase: true);

      runGeneralPurposeTest('handles many attachments', (
        provider,
        agent,
      ) async {
        // Create 10 small images using pre-loaded data
        final attachments = List.generate(
          10,
          (i) => DataPart(testImageBytes, mimeType: 'image/png'),
        );

        final result = await agent.send(
          'How many images are there?',
          attachments: attachments,
        );

        expect(result.output, isNotEmpty);
        // Verify all attachments are present
        final userMessage = result.messages.firstWhere(
          (m) => m.role == ChatMessageRole.user,
        );
        expect(userMessage.parts.whereType<DataPart>().length, equals(10));
      }, edgeCase: true);
    });
  });
}
