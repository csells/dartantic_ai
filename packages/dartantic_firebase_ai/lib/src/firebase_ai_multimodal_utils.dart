import 'dart:typed_data';
import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

/// Enhanced multi-modal support utilities for Firebase AI.
class FirebaseAIMultiModalUtils {
  static final Logger _logger = Logger(
    'dartantic.chat.models.firebase_ai.multimodal',
  );

  /// Validates if a media type is supported by Firebase AI Gemini models.
  static bool isSupportedMediaType(String mimeType) {
    // Firebase AI Gemini models support these media types
    const supportedTypes = {
      // Images
      'image/png',
      'image/jpeg', 
      'image/jpg', 
      'image/webp',
      'image/heic',
      'image/heif',
      
      // Audio (for future Gemini models)
      'audio/wav',
      'audio/mp3',
      'audio/aac',
      'audio/ogg',
      'audio/flac',
      
      // Video (for future Gemini models)
      'video/mp4',
      'video/mpeg',
      'video/mov',
      'video/avi',
      'video/x-flv',
      'video/mpg',
      'video/webm',
      'video/wmv',
      'video/3gpp',
      
      // Documents (limited support)
      'application/pdf',
      'text/plain',
      'text/html',
      'text/css',
      'text/javascript',
      'application/x-javascript',
      'text/x-typescript',
      'application/json',
      'text/xml',
      'application/xml',
      'text/csv',
      'text/markdown',
      'text/x-python',
      'text/x-java-source',
      'text/x-c',
      'text/x-c++src',
      'text/x-csharp',
      'text/x-php',
      'text/x-ruby',
      'text/x-go',
      'text/x-rust',
      'text/x-kotlin',
      'text/x-scala',
      'text/x-swift',
    };
    
    return supportedTypes.contains(mimeType.toLowerCase());
  }

  /// Gets the media category for a given MIME type.
  static MediaCategory getMediaCategory(String mimeType) {
    final type = mimeType.toLowerCase();
    
    if (type.startsWith('image/')) {
      return MediaCategory.image;
    } else if (type.startsWith('audio/')) {
      return MediaCategory.audio;
    } else if (type.startsWith('video/')) {
      return MediaCategory.video;
    } else if (type.startsWith('text/') || 
               type.startsWith('application/json') ||
               type.startsWith('application/xml') ||
               type.startsWith('application/pdf')) {
      return MediaCategory.document;
    }
    
    return MediaCategory.unknown;
  }

  /// Validates media content for Firebase AI compatibility.
  static MediaValidationResult validateMedia({
    required Uint8List bytes,
    required String mimeType,
    int? maxSizeBytes,
  }) {
    try {
      // Check if media type is supported
      if (!isSupportedMediaType(mimeType)) {
        return MediaValidationResult(
          isValid: false,
          error: 'Unsupported media type: $mimeType. Firebase AI supports '
                 'images, audio, video, and text documents.',
          category: getMediaCategory(mimeType),
        );
      }

      // Check file size limits (Firebase AI has size limits)
      final category = getMediaCategory(mimeType);
      final defaultMaxSize = _getDefaultMaxSize(category);
      final actualMaxSize = maxSizeBytes ?? defaultMaxSize;
      
      if (bytes.length > actualMaxSize) {
        final sizeMB = (bytes.length / (1024 * 1024)).toStringAsFixed(2);
        final maxSizeMB = (actualMaxSize / (1024 * 1024)).toStringAsFixed(2);
        
        return MediaValidationResult(
          isValid: false,
          error: 'File size ${sizeMB}MB exceeds maximum allowed size of '
                 '${maxSizeMB}MB for ${category.name} files.',
          category: category,
          actualSizeBytes: bytes.length,
          maxAllowedSizeBytes: actualMaxSize,
        );
      }

      // Additional validation for specific media types
      final specificValidation = _validateSpecificMediaType(bytes, mimeType);
      if (!specificValidation.isValid) {
        return specificValidation;
      }

      _logger.fine(
        'Validated ${category.name} media: $mimeType, '
        '${(bytes.length / 1024).toStringAsFixed(1)}KB',
      );

      return MediaValidationResult(
        isValid: true,
        category: category,
        actualSizeBytes: bytes.length,
        maxAllowedSizeBytes: actualMaxSize,
      );
    } on Exception catch (e, stackTrace) {
      _logger.warning(
        'Error validating media: $e',
        e,
        stackTrace,
      );
      
      return MediaValidationResult(
        isValid: false,
        error: 'Media validation failed: $e',
        category: getMediaCategory(mimeType),
      );
    }
  }

  /// Gets default max size for media category.
  static int _getDefaultMaxSize(MediaCategory category) {
    switch (category) {
      case MediaCategory.image:
        return 20 * 1024 * 1024; // 20MB for images  
      case MediaCategory.audio:
        return 50 * 1024 * 1024; // 50MB for audio
      case MediaCategory.video:
        return 100 * 1024 * 1024; // 100MB for video
      case MediaCategory.document:
        return 10 * 1024 * 1024; // 10MB for documents
      case MediaCategory.unknown:
        return 1 * 1024 * 1024; // 1MB for unknown types
    }
  }

  /// Performs specific validation for different media types.
  static MediaValidationResult _validateSpecificMediaType(
    Uint8List bytes,
    String mimeType,
  ) {
    final category = getMediaCategory(mimeType);
    
    try {
      switch (category) {
        case MediaCategory.image:
          return _validateImage(bytes, mimeType);
        case MediaCategory.audio:
          return _validateAudio(bytes, mimeType);
        case MediaCategory.video:
          return _validateVideo(bytes, mimeType);
        case MediaCategory.document:
          return _validateDocument(bytes, mimeType);
        case MediaCategory.unknown:
          return MediaValidationResult(
            isValid: false,
            error: 'Unknown media category for type: $mimeType',
            category: category,
          );
      }
    } on Exception catch (e) {
      return MediaValidationResult(
        isValid: false,
        error: 'Specific validation failed for $mimeType: $e',
        category: category,
      );
    }
  }

  static MediaValidationResult _validateImage(
      Uint8List bytes, String mimeType) {
    // Basic image file signature validation
    if (bytes.length < 8) {
      return const MediaValidationResult(
        isValid: false,
        error: 'Image file too small to be valid',
        category: MediaCategory.image,
      );
    }

    // Check basic file signatures
    final header = bytes.take(8).toList();
    
    switch (mimeType.toLowerCase()) {
      case 'image/png':
        // PNG signature: 89 50 4E 47 0D 0A 1A 0A
        if (header.length >= 8 &&
            header[0] == 0x89 && header[1] == 0x50 && 
            header[2] == 0x4E && header[3] == 0x47) {
          return const MediaValidationResult(
              isValid: true, category: MediaCategory.image);
        }
      case 'image/jpeg':
      case 'image/jpg':
        // JPEG signature: FF D8 FF
        if (header.length >= 3 &&
            header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF) {
          return const MediaValidationResult(
              isValid: true, category: MediaCategory.image);
        }
      case 'image/webp':
        // WebP signature: RIFF ... WEBP
        if (header.length >= 8 &&
            header[0] == 0x52 && header[1] == 0x49 && 
            header[2] == 0x46 && header[3] == 0x46) {
          return const MediaValidationResult(
              isValid: true, category: MediaCategory.image);
        }
      default:
        // For other image types, assume valid if size is reasonable
        return const MediaValidationResult(
            isValid: true, category: MediaCategory.image);
    }

    return MediaValidationResult(
      isValid: false,
      error: 'Invalid $mimeType file signature',
      category: MediaCategory.image,
    );
  }

  static MediaValidationResult _validateAudio(
      Uint8List bytes, String mimeType) {
    if (bytes.length < 4) {
      return const MediaValidationResult(
        isValid: false,
        error: 'Audio file too small to be valid',
        category: MediaCategory.audio,
      );
    }

    // For now, just check minimum size - could add more sophisticated
    // validation
    return const MediaValidationResult(
        isValid: true, category: MediaCategory.audio);
  }

  static MediaValidationResult _validateVideo(
      Uint8List bytes, String mimeType) {
    if (bytes.length < 8) {
      return const MediaValidationResult(
        isValid: false,
        error: 'Video file too small to be valid',
        category: MediaCategory.video,
      );
    }

    // For now, just check minimum size - could add more sophisticated
    // validation
    return const MediaValidationResult(
        isValid: true, category: MediaCategory.video);
  }

  static MediaValidationResult _validateDocument(
      Uint8List bytes, String mimeType) {
    if (bytes.isEmpty) {
      return const MediaValidationResult(
        isValid: false,  
        error: 'Document is empty',
        category: MediaCategory.document,
      );
    }

    // For text documents, could validate encoding
    if (mimeType.startsWith('text/')) {
      try {
        // Try to decode as UTF-8 to ensure it's valid text
        final text = String.fromCharCodes(bytes);
        if (text.isEmpty) {
          return const MediaValidationResult(
            isValid: false,
            error: 'Text document appears to be empty',
            category: MediaCategory.document,
          );
        }
      } on Exception {
        return const MediaValidationResult(
          isValid: false,
          error: 'Invalid text encoding in document',
          category: MediaCategory.document,
        );
      }
    }

    return const MediaValidationResult(
        isValid: true, category: MediaCategory.document);
  }

  /// Creates optimized DataPart for Firebase AI with validation.
  static DataPart? createOptimizedDataPart({
    required Uint8List bytes,
    required String mimeType,
    int? maxSizeBytes,
  }) {
    final validation = validateMedia(
      bytes: bytes,
      mimeType: mimeType,
      maxSizeBytes: maxSizeBytes,
    );

    if (!validation.isValid) {
      _logger.warning('Invalid media for DataPart: ${validation.error}');
      return null;
    }

    _logger.fine(
      'Creating optimized DataPart: ${validation.category?.name}, '
      '$mimeType, ${(bytes.length / 1024).toStringAsFixed(1)}KB',
    );

    return DataPart(bytes, mimeType: mimeType);
  }
}

/// Media validation result.
class MediaValidationResult {
  /// Creates a media validation result.
  const MediaValidationResult({
    required this.isValid,
    this.error,
    this.category,
    this.actualSizeBytes,
    this.maxAllowedSizeBytes,
  });

  /// Whether the media is valid.
  final bool isValid;
  
  /// Error message if validation failed.
  final String? error;
  
  /// Media category.
  final MediaCategory? category;
  
  /// Actual file size in bytes.
  final int? actualSizeBytes;
  
  /// Maximum allowed size in bytes.
  final int? maxAllowedSizeBytes;
}

/// Media categories supported by Firebase AI.
enum MediaCategory {
  /// Image media type.
  image,
  
  /// Audio media type.
  audio,
  
  /// Video media type.
  video,
  
  /// Document media type.
  document,
  
  /// Unknown media type.
  unknown,
}
