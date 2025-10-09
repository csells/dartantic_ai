/// TESTING PHILOSOPHY:
/// 1. DO NOT catch exceptions - let them bubble up for diagnosis
/// 2. DO NOT add provider filtering except by capabilities (e.g. ProviderCaps)
/// 3. DO NOT add performance tests
/// 4. DO NOT add regression tests
/// 5. 80% cases = common usage patterns tested across ALL capable providers
/// 6. Edge cases = rare scenarios tested on Google only to avoid timeouts
/// 7. Each functionality should only be tested in ONE file - no duplication

import 'dart:typed_data';
import 'package:dartantic_firebase_ai/src/firebase_ai_multimodal_utils.dart';
import 'package:test/test.dart';

void main() {
  group('FirebaseAIMultiModalUtils', () {
    group('Media Type Support', () {
      test('identifies supported image types', () {
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('image/png'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('image/jpeg'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('image/jpg'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('image/webp'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('image/heic'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('image/heif'),
          isTrue,
        );
      });

      test('identifies supported audio types', () {
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('audio/wav'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('audio/mp3'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('audio/aac'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('audio/ogg'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('audio/flac'),
          isTrue,
        );
      });

      test('identifies supported video types', () {
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('video/mp4'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('video/mpeg'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('video/mov'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('video/avi'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('video/webm'),
          isTrue,
        );
      });

      test('identifies supported document types', () {
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('application/pdf'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('text/plain'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('text/html'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('application/json'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('text/markdown'),
          isTrue,
        );
      });

      test('identifies unsupported media types', () {
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('application/exe'),
          isFalse,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('image/bmp'),
          isFalse,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('video/unsupported'),
          isFalse,
        );
      });

      test('handles case-insensitive media types', () {
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('IMAGE/PNG'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('Video/MP4'),
          isTrue,
        );
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('TEXT/PLAIN'),
          isTrue,
        );
      });
    });

    group('Media Category Detection', () {
      test('categorizes image types correctly', () {
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('image/png'),
          equals(MediaCategory.image),
        );
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('image/jpeg'),
          equals(MediaCategory.image),
        );
      });

      test('categorizes audio types correctly', () {
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('audio/wav'),
          equals(MediaCategory.audio),
        );
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('audio/mp3'),
          equals(MediaCategory.audio),
        );
      });

      test('categorizes video types correctly', () {
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('video/mp4'),
          equals(MediaCategory.video),
        );
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('video/mpeg'),
          equals(MediaCategory.video),
        );
      });

      test('categorizes document types correctly', () {
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('text/plain'),
          equals(MediaCategory.document),
        );
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('application/json'),
          equals(MediaCategory.document),
        );
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('application/pdf'),
          equals(MediaCategory.document),
        );
      });

      test('categorizes unknown types correctly', () {
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('application/unknown'),
          equals(MediaCategory.unknown),
        );
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('weird/type'),
          equals(MediaCategory.unknown),
        );
      });

      test('handles case-insensitive categorization', () {
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('IMAGE/PNG'),
          equals(MediaCategory.image),
        );
        expect(
          FirebaseAIMultiModalUtils.getMediaCategory('VIDEO/MP4'),
          equals(MediaCategory.video),
        );
      });
    });

    group('Media Validation', () {
      test('validates supported media with valid size', () {
        final bytes = _createPngBytes();
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: bytes,
          mimeType: 'image/png',
        );

        expect(result.isValid, isTrue);
        expect(result.error, isNull);
        expect(result.category, equals(MediaCategory.image));
        expect(result.actualSizeBytes, equals(bytes.length));
      });

      test('rejects unsupported media types', () {
        final bytes = Uint8List.fromList([1, 2, 3, 4]);
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: bytes,
          mimeType: 'application/exe',
        );

        expect(result.isValid, isFalse);
        expect(result.error, contains('Unsupported media type'));
        expect(result.category, equals(MediaCategory.unknown));
      });

      test('rejects oversized images', () {
        final bytes = Uint8List(25 * 1024 * 1024); // 25MB
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: bytes,
          mimeType: 'image/png',
        );

        expect(result.isValid, isFalse);
        expect(result.error, contains('exceeds maximum allowed size'));
        expect(result.actualSizeBytes, equals(bytes.length));
        expect(result.maxAllowedSizeBytes, equals(20 * 1024 * 1024));
      });

      test('respects custom max size limits', () {
        final bytes = Uint8List(5 * 1024 * 1024); // 5MB
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: bytes,
          mimeType: 'image/png',
          maxSizeBytes: 1 * 1024 * 1024, // 1MB limit
        );

        expect(result.isValid, isFalse);
        expect(result.error, contains('exceeds maximum allowed size'));
        expect(result.maxAllowedSizeBytes, equals(1 * 1024 * 1024));
      });

      test('handles validation exceptions gracefully', () {
        // This should trigger an exception during validation
        final bytes = Uint8List(0);
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: bytes,
          mimeType: 'image/png',
        );

        expect(result.isValid, isFalse);
        expect(result.error, contains('too small to be valid'));
      });
    });

    group('Image Validation', () {
      test('validates PNG signature correctly', () {
        final pngBytes = _createPngBytes();
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: pngBytes,
          mimeType: 'image/png',
        );

        expect(result.isValid, isTrue);
        expect(result.category, equals(MediaCategory.image));
      });

      test('validates JPEG signature correctly', () {
        final jpegBytes = _createJpegBytes();
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: jpegBytes,
          mimeType: 'image/jpeg',
        );

        expect(result.isValid, isTrue);
        expect(result.category, equals(MediaCategory.image));
      });

      test('validates WebP signature correctly', () {
        final webpBytes = _createWebpBytes();
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: webpBytes,
          mimeType: 'image/webp',
        );

        expect(result.isValid, isTrue);
        expect(result.category, equals(MediaCategory.image));
      });

      test('rejects image files that are too small', () {
        final tinyBytes = Uint8List.fromList([1, 2, 3]); // Too small
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: tinyBytes,
          mimeType: 'image/png',
        );

        expect(result.isValid, isFalse);
        expect(result.error, contains('too small to be valid'));
      });

      test('rejects images with invalid signatures', () {
        final invalidBytes = Uint8List.fromList([
          0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]);
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: invalidBytes,
          mimeType: 'image/png',
        );

        expect(result.isValid, isFalse);
        expect(result.error, contains('Invalid image/png file signature'));
      });

      test('assumes validity for other image types', () {
        final genericBytes = Uint8List.fromList([
          0x48, 0x45, 0x49, 0x43, 0x00, 0x00, 0x00, 0x00
        ]);
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: genericBytes,
          mimeType: 'image/heic',
        );

        expect(result.isValid, isTrue);
        expect(result.category, equals(MediaCategory.image));
      });
    });

    group('Audio Validation', () {
      test('validates audio files with sufficient size', () {
        final audioBytes = Uint8List.fromList([
          0x52, 0x49, 0x46, 0x46, 0x24, 0x08, 0x00, 0x00
        ]);
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: audioBytes,
          mimeType: 'audio/wav',
        );

        expect(result.isValid, isTrue);
        expect(result.category, equals(MediaCategory.audio));
      });

      test('rejects audio files that are too small', () {
        final tinyBytes = Uint8List.fromList([1, 2]); // Too small
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: tinyBytes,
          mimeType: 'audio/wav',
        );

        expect(result.isValid, isFalse);
        expect(result.error, contains('too small to be valid'));
      });
    });

    group('Video Validation', () {
      test('validates video files with sufficient size', () {
        final videoBytes = Uint8List.fromList([
          0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70
        ]);
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: videoBytes,
          mimeType: 'video/mp4',
        );

        expect(result.isValid, isTrue);
        expect(result.category, equals(MediaCategory.video));
      });

      test('rejects video files that are too small', () {
        final tinyBytes = Uint8List.fromList([1, 2, 3]); // Too small
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: tinyBytes,
          mimeType: 'video/mp4',
        );

        expect(result.isValid, isFalse);
        expect(result.error, contains('too small to be valid'));
      });
    });

    group('Document Validation', () {
      test('validates text documents', () {
        final textBytes = Uint8List.fromList('Hello, world!'.codeUnits);
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: textBytes,
          mimeType: 'text/plain',
        );

        expect(result.isValid, isTrue);
        expect(result.category, equals(MediaCategory.document));
      });

      test('validates JSON documents', () {
        final jsonBytes = Uint8List.fromList('{"key": "value"}'.codeUnits);
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: jsonBytes,
          mimeType: 'application/json',
        );

        expect(result.isValid, isTrue);
        expect(result.category, equals(MediaCategory.document));
      });

      test('rejects empty documents', () {
        final emptyBytes = Uint8List(0);
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: emptyBytes,
          mimeType: 'text/plain',
        );

        expect(result.isValid, isFalse);
        expect(result.error, contains('Document is empty'));
      });

      test('rejects text documents with empty content', () {
        final emptyTextBytes = Uint8List.fromList(''.codeUnits);
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: emptyTextBytes,
          mimeType: 'text/plain',
        );

        expect(result.isValid, isFalse);
        expect(result.error, contains('Document is empty'));
      });

      test('validates non-text documents without text validation', () {
        final pdfBytes = Uint8List.fromList([
          0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34
        ]);
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: pdfBytes,
          mimeType: 'application/pdf',
        );

        expect(result.isValid, isTrue);
        expect(result.category, equals(MediaCategory.document));
      });
    });

    group('Size Limits', () {
      test('applies correct default size limits for images', () {
        // Create a valid PNG with some padding to reach 10MB
        final pngHeader = _createPngBytes();
        final padding = Uint8List(10 * 1024 * 1024 - pngHeader.length);
        final fullBytes = Uint8List.fromList([...pngHeader, ...padding]);
        
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: fullBytes,
          mimeType: 'image/png',
        );
        expect(result.isValid, isTrue);
        expect(result.maxAllowedSizeBytes, equals(20 * 1024 * 1024));
      });

      test('applies correct default size limits for audio', () {
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: Uint8List(30 * 1024 * 1024), // 30MB - within limit
          mimeType: 'audio/wav',
        );
        expect(result.isValid, isTrue);
        expect(result.maxAllowedSizeBytes, equals(50 * 1024 * 1024));
      });

      test('applies correct default size limits for video', () {
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: Uint8List(80 * 1024 * 1024), // 80MB - within limit
          mimeType: 'video/mp4',
        );
        expect(result.isValid, isTrue);
        expect(result.maxAllowedSizeBytes, equals(100 * 1024 * 1024));
      });

      test('applies correct default size limits for documents', () {
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: Uint8List.fromList('test content'.codeUnits),
          mimeType: 'text/plain',
        );
        expect(result.isValid, isTrue);
        expect(result.maxAllowedSizeBytes, equals(10 * 1024 * 1024));
      });

      test('applies correct default size limits for unknown types', () {
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: Uint8List(512 * 1024), // 512KB - within limit
          mimeType: 'unknown/type',
        );
        expect(result.isValid, isFalse); // Unsupported type
      });
    });

    group('DataPart Creation', () {
      test('creates DataPart for valid media', () {
        final bytes = _createPngBytes();
        final dataPart = FirebaseAIMultiModalUtils.createOptimizedDataPart(
          bytes: bytes,
          mimeType: 'image/png',
        );

        expect(dataPart, isNotNull);
        expect(dataPart!.bytes, equals(bytes));
        expect(dataPart.mimeType, equals('image/png'));
      });

      test('returns null for invalid media', () {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final dataPart = FirebaseAIMultiModalUtils.createOptimizedDataPart(
          bytes: bytes,
          mimeType: 'unsupported/type',
        );

        expect(dataPart, isNull);
      });

      test('respects custom size limits in DataPart creation', () {
        final bytes = Uint8List(5 * 1024 * 1024); // 5MB
        final dataPart = FirebaseAIMultiModalUtils.createOptimizedDataPart(
          bytes: bytes,
          mimeType: 'image/png',
          maxSizeBytes: 1 * 1024 * 1024, // 1MB limit
        );

        expect(dataPart, isNull); // Should be null due to size limit
      });

      test('creates DataPart with custom size limits when valid', () {
        // Create a valid PNG with padding to reach 512KB
        final pngHeader = _createPngBytes();
        final padding = Uint8List(512 * 1024 - pngHeader.length);
        final fullBytes = Uint8List.fromList([...pngHeader, ...padding]);
        
        final dataPart = FirebaseAIMultiModalUtils.createOptimizedDataPart(
          bytes: fullBytes,
          mimeType: 'image/png',
          maxSizeBytes: 1 * 1024 * 1024, // 1MB limit
        );

        expect(dataPart, isNotNull);
        expect(dataPart!.bytes.length, equals(512 * 1024));
      });
    });

    group('Edge Cases', () {
      test('handles null/empty inputs gracefully', () {
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: Uint8List(0),
          mimeType: '',
        );
        expect(result.isValid, isFalse);
      });

      test('handles very large content types', () {
        final result = FirebaseAIMultiModalUtils.validateMedia(
          bytes: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
          mimeType: 'application/very-long-and-complex-mime-type-that-should-still-work',
        );
        expect(result.isValid, isFalse); // Unsupported, but shouldn't crash
      });

      test('handles special characters in MIME types', () {
        expect(
          FirebaseAIMultiModalUtils.isSupportedMediaType('text/plain; charset=utf-8'),
          isFalse, // Should not match due to extra parameters
        );
      });
    });
  });

  group('MediaValidationResult', () {
    test('creates result with all properties', () {
      const result = MediaValidationResult(
        isValid: true,
        error: null,
        category: MediaCategory.image,
        actualSizeBytes: 1024,
        maxAllowedSizeBytes: 2048,
      );

      expect(result.isValid, isTrue);
      expect(result.error, isNull);
      expect(result.category, equals(MediaCategory.image));
      expect(result.actualSizeBytes, equals(1024));
      expect(result.maxAllowedSizeBytes, equals(2048));
    });

    test('creates error result', () {
      const result = MediaValidationResult(
        isValid: false,
        error: 'Test error',
        category: MediaCategory.unknown,
      );

      expect(result.isValid, isFalse);
      expect(result.error, equals('Test error'));
      expect(result.category, equals(MediaCategory.unknown));
      expect(result.actualSizeBytes, isNull);
      expect(result.maxAllowedSizeBytes, isNull);
    });
  });

  group('MediaCategory Enum', () {
    test('has all expected values', () {
      expect(MediaCategory.values, hasLength(5));
      expect(MediaCategory.values, contains(MediaCategory.image));
      expect(MediaCategory.values, contains(MediaCategory.audio));
      expect(MediaCategory.values, contains(MediaCategory.video));
      expect(MediaCategory.values, contains(MediaCategory.document));
      expect(MediaCategory.values, contains(MediaCategory.unknown));
    });

    test('enum names are correct', () {
      expect(MediaCategory.image.name, equals('image'));
      expect(MediaCategory.audio.name, equals('audio'));
      expect(MediaCategory.video.name, equals('video'));
      expect(MediaCategory.document.name, equals('document'));
      expect(MediaCategory.unknown.name, equals('unknown'));
    });
  });
}

// Test helper functions
Uint8List _createPngBytes() {
  // Valid PNG signature
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  ]);
}

Uint8List _createJpegBytes() {
  // Valid JPEG signature
  return Uint8List.fromList([
    0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
    0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48,
  ]);
}

Uint8List _createWebpBytes() {
  // Valid WebP signature (RIFF header)
  return Uint8List.fromList([
    0x52, 0x49, 0x46, 0x46, 0x24, 0x08, 0x00, 0x00,
    0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x4C,
  ]);
}