import 'dart:convert';
import 'dart:typed_data';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:openai_core/openai_core.dart' as openai;

import 'openai_responses_attachment_types.dart';

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

  // Map of outputIndex → image data for tracking multiple concurrent images
  final Map<int, String> _imagesByIndex = {};
  final Set<int> _completedImageIndices = {};

  final Set<({String containerId, String fileId})> _containerFiles = {};

  /// Records a partial image update during streaming.
  void recordPartialImage({required String base64, required int index}) {
    _imagesByIndex[index] = base64;
    _logger.fine('Stored partial image at index: $index');
  }

  /// Marks image generation as completed with optional final result.
  void markImageGenerationCompleted({
    required int index,
    String? resultBase64,
  }) {
    _completedImageIndices.add(index);
    if (resultBase64 != null && resultBase64.isNotEmpty) {
      _imagesByIndex[index] = resultBase64;
    }
  }

  /// Registers a completed image generation call.
  void registerImageCall(openai.ImageGenerationCall call, int index) {
    markImageGenerationCompleted(index: index, resultBase64: call.resultBase64);
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
    attachments.addAll(_resolveImageAttachments());

    if (_containerFiles.isNotEmpty) {
      attachments.addAll(await _resolveContainerAttachments());
    }

    return attachments;
  }

  List<DataPart> _resolveImageAttachments() {
    final parts = <DataPart>[];

    for (final index in _completedImageIndices) {
      final base64Data = _imagesByIndex[index];
      if (base64Data == null) continue;

      final decodedBytes = Uint8List.fromList(base64Decode(base64Data));
      // Use lookupMimeType with headerBytes to detect MIME type from file
      // signature
      final inferredMime =
          lookupMimeType('image.bin', headerBytes: decodedBytes) ??
          'application/octet-stream';
      final extension = Part.extensionFromMimeType(inferredMime);
      final baseName = 'image_$index';

      // Build filename with extension if available (extension lacks dot prefix)
      final imageName = extension != null ? '$baseName.$extension' : baseName;

      parts.add(
        DataPart(decodedBytes, mimeType: inferredMime, name: imageName),
      );
    }

    return parts;
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
