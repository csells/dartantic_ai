import 'dart:convert';
import 'dart:typed_data';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:openai_core/openai_core.dart' as openai;

import 'openai_responses_event_mapper.dart';

/// Collects and resolves attachments (images, container files) during
/// streaming.
class AttachmentCollector {
  /// Creates a new attachment collector.
  AttachmentCollector({
    required Logger logger,
    required ContainerFileLoader containerFileLoader,
  }) : _logger = logger,
       _containerFileLoader = containerFileLoader;

  final Logger _logger;
  final ContainerFileLoader _containerFileLoader;

  String? _latestImageBase64;
  int? _latestImageIndex;
  bool _imageGenerationCompleted = false;

  final Set<({String containerId, String fileId})> _containerFiles = {};

  /// Records a partial image update during streaming.
  void recordPartialImage({required String base64, required int index}) {
    _latestImageBase64 = base64;
    _latestImageIndex = index;
    _logger.fine('Stored partial image index: $_latestImageIndex');
  }

  /// Marks image generation as completed with optional final result.
  void markImageGenerationCompleted({String? resultBase64}) {
    _imageGenerationCompleted = true;
    if (resultBase64 != null && resultBase64.isNotEmpty) {
      _latestImageBase64 = resultBase64;
    }
  }

  /// Registers a completed image generation call.
  void registerImageCall(openai.ImageGenerationCall call) {
    markImageGenerationCompleted(resultBase64: call.resultBase64);
  }

  /// Tracks a container file citation for later download.
  void trackContainerCitation({
    required String containerId,
    required String fileId,
  }) {
    _containerFiles.add((containerId: containerId, fileId: fileId));
  }

  /// Resolves all tracked attachments into DataParts.
  Future<List<DataPart>> resolveAttachments() async {
    final attachments = <DataPart>[];
    final imageParts = _resolveImageAttachments();
    if (imageParts != null) {
      attachments.add(imageParts);
    }

    if (_containerFiles.isNotEmpty) {
      attachments.addAll(await _resolveContainerAttachments());
    }

    return attachments;
  }

  DataPart? _resolveImageAttachments() {
    if (!_imageGenerationCompleted || _latestImageBase64 == null) {
      return null;
    }

    final decodedBytes = Uint8List.fromList(base64Decode(_latestImageBase64!));
    // Use lookupMimeType with headerBytes to detect MIME type from file
    // signature
    final inferredMime =
        lookupMimeType('image.bin', headerBytes: decodedBytes) ??
        'application/octet-stream';
    final extension = Part.extensionFromMimeType(inferredMime);
    final baseName = 'image_${_latestImageIndex ?? 0}';

    // Build filename with extension if available (extension lacks dot prefix)
    final imageName = extension != null ? '$baseName.$extension' : baseName;

    return DataPart(decodedBytes, mimeType: inferredMime, name: imageName);
  }

  Future<List<DataPart>> _resolveContainerAttachments() async {
    final attachments = <DataPart>[];

    for (final citation in _containerFiles) {
      final containerId = citation.containerId;
      final fileId = citation.fileId;
      _logger.info('Downloading container file: $fileId from $containerId');
      final data = await _containerFileLoader(containerId, fileId);

      final inferredMime =
          data.mimeType ??
          lookupMimeType(data.fileName ?? '', headerBytes: data.bytes) ??
          'application/octet-stream';
      final extension = Part.extensionFromMimeType(inferredMime);
      final fileName =
          data.fileName ?? (extension != null ? '$fileId.$extension' : fileId);

      attachments.add(
        DataPart(data.bytes, mimeType: inferredMime, name: fileName),
      );
      _logger.info(
        'Added container file as DataPart '
        '(${data.bytes.length} bytes, mime: $inferredMime)',
      );
    }

    _containerFiles.clear();
    return attachments;
  }
}
