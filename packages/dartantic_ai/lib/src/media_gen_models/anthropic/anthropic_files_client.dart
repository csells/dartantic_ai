import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

import '../../retry_http_client.dart';

/// Lightweight client for interacting with Anthropic's Files API.
class AnthropicFilesClient {
  /// Creates a new Anthropic files API client.
  AnthropicFilesClient({
    required this.apiKey,
    required List<String> betaFeatures,
    Uri? baseUrl,
    http.Client? client,
    Map<String, String>? headers,
  }) : _betaHeader = _composeBetaHeader(betaFeatures),
       _baseUri = baseUrl ?? Uri.parse('https://api.anthropic.com/'),
       _client = client ?? RetryHttpClient(inner: http.Client()),
       _customHeaders = headers ?? const {};

  static final Logger _logger = Logger('dartantic.media.anthropic.files');

  /// API key used for authenticated Anthropic requests.
  final String apiKey;
  final String _betaHeader;
  final Uri _baseUri;
  final http.Client _client;
  final Map<String, String> _customHeaders;

  static String _composeBetaHeader(List<String> features) {
    final betaFlags = <String>{
      'files-api-2025-04-14',
      'code-execution-2025-08-25',
      ...features,
    };
    return betaFlags.join(',');
  }

  /// Downloads a file's metadata and content from Anthropic.
  Future<DownloadedAnthropicFile> download(String fileId) async {
    final metadata = await _metadata(fileId);
    final bytes = await _contentBytes(fileId);
    return DownloadedAnthropicFile(
      bytes: bytes,
      filename: metadata.filename,
      mimeType: metadata.mimeType,
    );
  }

  /// Lists files available via the Anthropic Files API.
  Future<List<AnthropicRemoteFile>> list({int? limit}) async {
    final query = <String, String>{if (limit != null) 'limit': '$limit'};
    final uri = _baseUri.resolveUri(
      Uri(path: '/v1/files', queryParameters: query),
    );

    final response = await _client.get(
      uri,
      headers: _headers(accept: 'application/json'),
    );

    if (response.statusCode != 200) {
      _logger.warning(
        'Failed to list Anthropic files: '
        'HTTP ${response.statusCode} ${response.body}',
      );
      throw Exception(
        'Failed to list Anthropic files: '
        'HTTP ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'];
    if (data is! List) return const [];

    return data
        .whereType<Map<String, Object?>>()
        .map(AnthropicRemoteFile.fromJson)
        .toList(growable: false);
  }

  Future<_AnthropicFileMetadata> _metadata(String fileId) async {
    final uri = _baseUri.resolve('/v1/files/$fileId');
    final response = await _client.get(
      uri,
      headers: _headers(accept: 'application/json'),
    );

    if (response.statusCode != 200) {
      _logger.warning(
        'Failed to fetch Anthropic file metadata ($fileId): '
        'HTTP ${response.statusCode} ${response.body}',
      );
      throw Exception(
        'Failed to fetch Anthropic file metadata ($fileId): '
        'HTTP ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return _AnthropicFileMetadata(
      filename: body['filename'] as String?,
      mimeType: body['mime_type'] as String? ?? body['mimeType'] as String?,
    );
  }

  Future<Uint8List> _contentBytes(String fileId) async {
    final uri = _baseUri.resolve('/v1/files/$fileId/content');
    final response = await _client.get(
      uri,
      headers: _headers(accept: 'application/octet-stream'),
    );

    if (response.statusCode != 200) {
      _logger.warning(
        'Failed to download Anthropic file ($fileId): '
        'HTTP ${response.statusCode} ${response.body}',
      );
      throw Exception(
        'Failed to download Anthropic file ($fileId): '
        'HTTP ${response.statusCode} ${response.body}',
      );
    }

    return Uint8List.fromList(response.bodyBytes);
  }

  Map<String, String> _headers({required String accept}) => {
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01',
    'anthropic-beta': _betaHeader,
    'accept': accept,
    ..._customHeaders,
  };

  /// Releases the underlying HTTP client.
  void close() {
    _client.close();
  }
}

class _AnthropicFileMetadata {
  const _AnthropicFileMetadata({this.filename, this.mimeType});

  final String? filename;
  final String? mimeType;
}

/// Lightweight descriptor for files returned by the Anthropic Files API.
class AnthropicRemoteFile {
  /// Creates a new remote file descriptor.
  const AnthropicRemoteFile({
    required this.id,
    this.filename,
    this.mimeType,
    this.createdAt,
  });

  /// Builds a descriptor from Files API JSON.
  factory AnthropicRemoteFile.fromJson(Map<String, Object?> json) {
    final createdAt = json['created_at'];
    DateTime? parsedCreatedAt;
    if (createdAt is String) {
      parsedCreatedAt = DateTime.tryParse(createdAt)?.toUtc();
    }
    return AnthropicRemoteFile(
      id: json['id'] as String? ?? '',
      filename: json['filename'] as String?,
      mimeType: json['mime_type'] as String? ?? json['mimeType'] as String?,
      createdAt: parsedCreatedAt,
    );
  }

  /// Unique file identifier.
  final String id;

  /// Optional filename reported by Anthropic.
  final String? filename;

  /// Optional MIME type reported by Anthropic.
  final String? mimeType;

  /// Creation timestamp (UTC) if supplied.
  final DateTime? createdAt;
}

/// Container for downloaded Anthropic file contents.
class DownloadedAnthropicFile {
  /// Creates a container for downloaded Anthropic file bytes.
  const DownloadedAnthropicFile({
    required this.bytes,
    this.filename,
    this.mimeType,
  });

  /// Raw file bytes returned from Anthropic.
  final Uint8List bytes;

  /// Optional filename advertised by the API.
  final String? filename;

  /// Optional MIME type advertised by the API.
  final String? mimeType;
}
