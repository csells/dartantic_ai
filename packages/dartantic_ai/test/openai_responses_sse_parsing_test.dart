import 'dart:async';
import 'dart:convert';

import 'package:dartantic_ai/dartantic_ai.dart';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

// Mock HTTP client that returns StreamedResponse
class MockStreamingClient extends http.BaseClient {
  MockStreamingClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

void main() {
  group('OpenAI Responses SSE Parsing', () {
    test('web_search call lifecycle emits metadata', () async {
      // Create a mock SSE stream with web search events
      final sseEvents = [
        'event: response.created',
        'data: {"response": {"id": "resp_123"}}',
        '',
        'event: response.web_search_call.searching',
        'data: {"query": "minimalist logo trends 2025"}',
        '',
        'event: response.web_search_call.completed',
        'data: {"results": [{"url": "example.com", "title": "Logo Trends"}]}',
        '',
        'event: response.output_text.delta',
        'data: {"delta": "Here are the search results..."}',
        '',
        'event: response.completed',
        // ignore: lines_longer_than_80_chars
        'data: {"response": {"usage": {"input_tokens": 10, "output_tokens": 20}}}',
        '',
      ];

      final mockClient = MockStreamingClient((request) async {
        expect(request.url.path, endsWith('/responses'));
        expect(request.headers['Accept'], 'text/event-stream');

        // Return SSE stream
        final controller = StreamController<List<int>>();

        // Schedule events to be added asynchronously
        Timer.run(() async {
          for (final line in sseEvents) {
            controller.add(utf8.encode('$line\n'));
          }
          await controller.close();
        });

        return http.StreamedResponse(
          controller.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OpenAIResponsesChatModel(
        name: 'gpt-4o',
        apiKey: 'test-key',
        client: mockClient,
      );

      final messages = [
        const ChatMessage(
          role: ChatMessageRole.user,
          parts: [TextPart('Test search')],
        ),
      ];

      var foundWebSearchMetadata = false;
      var foundSearchingStage = false;
      var foundCompletedStage = false;

      await for (final chunk in model.sendStream(messages)) {
        final metadata = chunk.metadata;

        if (metadata.containsKey('web_search')) {
          foundWebSearchMetadata = true;
          final webSearch = metadata['web_search'] as Map;
          final stage = webSearch['stage'];

          if (stage == 'searching') {
            foundSearchingStage = true;
            expect(webSearch['data'], isA<Map>());
            final data = webSearch['data'] as Map;
            expect(data['query'], 'minimalist logo trends 2025');
          } else if (stage == 'completed') {
            foundCompletedStage = true;
            expect(webSearch['data'], isA<Map>());
          }
        }
      }

      expect(
        foundWebSearchMetadata,
        isTrue,
        reason: 'Should emit web_search metadata',
      );
      expect(
        foundSearchingStage,
        isTrue,
        reason: 'Should emit searching stage',
      );
      expect(
        foundCompletedStage,
        isTrue,
        reason: 'Should emit completed stage',
      );
    });

    test('image base64 assembly decodes to PNG', () async {
      // Create a valid PNG header followed by minimal PNG data
      // PNG signature: 89 50 4E 47 0D 0A 1A 0A
      const pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      // IHDR chunk (13 bytes): length(4) + type(4) + data(13) + crc(4)
      const ihdrChunk = [
        0x00, 0x00, 0x00, 0x0D, // Length: 13
        0x49, 0x48, 0x44, 0x52, // Type: IHDR
        0x00, 0x00, 0x00, 0x01, // Width: 1
        0x00, 0x00, 0x00, 0x01, // Height: 1
        0x08, 0x02, // Bit depth: 8, Color type: 2 (RGB)
        0x00, 0x00, 0x00, // Compression, Filter, Interlace
        0x00, 0x00, 0x00, 0x00, // CRC (simplified)
      ];
      // IEND chunk
      const iendChunk = [
        0x00, 0x00, 0x00, 0x00, // Length: 0
        0x49, 0x45, 0x4E, 0x44, // Type: IEND
        0xAE, 0x42, 0x60, 0x82, // CRC
      ];

      final minimalPng = [...pngHeader, ...ihdrChunk, ...iendChunk];
      final base64Png = base64.encode(minimalPng);

      // Split base64 into chunks to simulate streaming
      final chunk1 = base64Png.substring(0, base64Png.length ~/ 2);
      final chunk2 = base64Png.substring(base64Png.length ~/ 2);

      final sseEvents = [
        'event: response.created',
        'data: {"response": {"id": "resp_456"}}',
        '',
        'event: response.output_item.added',
        'data: {"item": {"id": "img_789", "type": "output_image", "mime_type": "image/png"}}',
        '',
        'event: response.image_generation.delta',
        'data: {"item_id": "img_789", "delta": {"data": "$chunk1"}}',
        '',
        'event: response.image_generation.delta',
        'data: {"item_id": "img_789", "delta": {"data": "$chunk2"}}',
        '',
        'event: response.image_generation.completed',
        'data: {"item_id": "img_789"}',
        '',
        'event: response.completed',
        // ignore: lines_longer_than_80_chars
        'data: {"response": {"usage": {"input_tokens": 5, "output_tokens": 10}}}',
        '',
      ];

      final mockClient = MockStreamingClient((request) async {
        final controller = StreamController<List<int>>();

        // Schedule events to be sent after returning the response
        Timer.run(() async {
          for (final line in sseEvents) {
            controller.add(utf8.encode('$line\n'));
          }
          await controller.close();
        });

        return http.StreamedResponse(
          controller.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OpenAIResponsesChatModel(
        name: 'gpt-4o',
        apiKey: 'test-key',
        client: mockClient,
      );

      final messages = [
        const ChatMessage(
          role: ChatMessageRole.user,
          parts: [TextPart('Generate image')],
        ),
      ];

      var foundImageData = false;
      var foundImageGenerationMetadata = false;
      List<int>? receivedBytes;

      await for (final chunk in model.sendStream(messages)) {
        // Check for image generation metadata
        if (chunk.metadata.containsKey('image_generation')) {
          foundImageGenerationMetadata = true;
        }

        // Check for actual image data
        for (final msg in chunk.messages) {
          for (final part in msg.parts) {
            if (part is DataPart && part.mimeType.contains('png')) {
              foundImageData = true;
              receivedBytes = part.bytes;

              // Verify PNG signature
              expect(
                receivedBytes.length,
                greaterThanOrEqualTo(8),
                reason: 'PNG must be at least 8 bytes',
              );

              for (var i = 0; i < 8; i++) {
                expect(
                  receivedBytes[i],
                  pngHeader[i],
                  reason: 'PNG signature byte $i mismatch',
                );
              }
            }
          }
        }
      }

      expect(
        foundImageGenerationMetadata,
        isTrue,
        reason: 'Should emit image_generation metadata',
      );
      expect(foundImageData, isTrue, reason: 'Should emit decoded PNG data');
      expect(
        receivedBytes,
        isNotNull,
        reason: 'Should have received image bytes',
      );
    });

    test('handles malformed base64 gracefully', () async {
      // Create SSE events with invalid base64
      final sseEvents = [
        'event: response.created',
        'data: {"response": {"id": "resp_bad"}}',
        '',
        'event: response.output_item.added',
        'data: {"item": {"id": "img_bad", "type": "output_image", "mime_type": "image/png"}}',
        '',
        'event: response.image_generation.delta',
        // Invalid base64 with spaces and newlines that need normalization
        r'data: {"item_id": "img_bad", "delta": {"data": "iVBORw0KGgo AAAANSU\nhEUg=="}}',
        '',
        'event: response.image_generation.completed',
        'data: {"item_id": "img_bad"}',
        '',
        'event: response.completed',
        'data: {"response": {}}',
        '',
      ];

      final mockClient = MockStreamingClient((request) async {
        final controller = StreamController<List<int>>();

        // Schedule events to be sent after returning the response
        Timer.run(() async {
          for (final line in sseEvents) {
            controller.add(utf8.encode('$line\n'));
          }
          await controller.close();
        });

        return http.StreamedResponse(
          controller.stream,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final model = OpenAIResponsesChatModel(
        name: 'gpt-4o',
        apiKey: 'test-key',
        client: mockClient,
      );

      final messages = [
        const ChatMessage(
          role: ChatMessageRole.user,
          parts: [TextPart('Test malformed')],
        ),
      ];

      // Should complete without throwing
      await model.sendStream(messages).toList();
      // If we got here, the stream didn't crash on malformed base64
      expect(true, isTrue);
    });
  });
}
