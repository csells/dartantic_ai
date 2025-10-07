import 'dart:typed_data';

/// Loads a container file by identifier and returns its resolved data.
typedef ContainerFileLoader =
    Future<ContainerFileData> Function(String containerId, String fileId);

/// Resolved data for a downloaded container file, including metadata hints.
class ContainerFileData {
  /// Creates a new [ContainerFileData] instance.
  const ContainerFileData({required this.bytes, this.fileName, this.mimeType});

  /// Raw file bytes returned by the API.
  final Uint8List bytes;

  /// Optional filename hint supplied by the provider.
  final String? fileName;

  /// Optional MIME type hint supplied by the provider.
  final String? mimeType;
}
