import 'dart:convert';
import 'dart:typed_data';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';

import '../../chat_models/anthropic_chat/anthropic_server_side_tool_types.dart';
import 'anthropic_files_client.dart';

/// Tracks Anthropic server-side tool events and converts deliverables to
/// dartantic parts.
class AnthropicToolDeliverableTracker {
  /// Creates a tracker capable of downloading and materializing tool outputs.
  AnthropicToolDeliverableTracker(
    this._filesClient, {
    required Set<String> targetMimeTypes,
  }) : _targetMimeTypes = targetMimeTypes,
       _startTime = DateTime.now().toUtc();

  static final Logger _logger = Logger(
    'dartantic.media.anthropic.tool_deliverables',
  );

  final AnthropicFilesClient _filesClient;
  final Set<String> _targetMimeTypes;
  final DateTime _startTime;
  final Set<String> _downloadedFileIds = <String>{};
  final Set<String> _emittedImageHashes = <String>{};
  final Map<String, List<Map<String, Object?>>> _toolEventLog = {
    AnthropicServerToolTypes.codeExecution: <Map<String, Object?>>[],
    AnthropicServerToolTypes.textEditorCodeExecution: <Map<String, Object?>>[],
    AnthropicServerToolTypes.bashCodeExecution: <Map<String, Object?>>[],
    AnthropicServerToolTypes.webSearch: <Map<String, Object?>>[],
    AnthropicServerToolTypes.webFetch: <Map<String, Object?>>[],
  };
  final Set<String> _seenRemoteFileIds = <String>{};
  final Set<String> _seenSearchUrls = <String>{};
  final Set<String> _seenFetchUrls = <String>{};
  final Set<String> _processedFetchEvents = <String>{};

  int _inlineImageCounter = 0;
  int _webFetchDocumentCounter = 0;

  /// Collects any inline [DataPart]s emitted within message parts.
  List<Part> collectMessageAssets(List<ChatMessage> messages) {
    final assets = <Part>[];
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is DataPart) assets.add(part);
      }
    }
    return assets;
  }

  /// Collects any [LinkPart]s emitted within message parts.
  List<LinkPart> collectMessageLinks(List<ChatMessage> messages) {
    final links = <LinkPart>[];
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is LinkPart) links.add(part);
      }
    }
    return links;
  }

  /// Processes tool metadata emitted during streaming, returning any new
  /// deliverables.
  Future<ToolDeliverableEmission> handleMetadata(
    Map<String, dynamic> metadata,
  ) async {
    final containerId = metadata['container_id'];
    if (containerId is String && containerId.isNotEmpty) {
      _logger.fine('Tracked Anthropic container id: $containerId');
    }

    final assets = <Part>[];
    final links = <LinkPart>[];
    for (final entry in metadata.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is! List) continue;

      for (final rawEvent in value) {
        if (rawEvent is! Map<String, Object?>) continue;
        _recordToolEvent(key, rawEvent);

        if (key == AnthropicServerToolTypes.codeExecution ||
            key == AnthropicServerToolTypes.textEditorCodeExecution ||
            key == AnthropicServerToolTypes.bashCodeExecution) {
          final deliverables = await _handleCodeExecutionEvent(rawEvent);
          assets.addAll(deliverables);
          continue;
        }

        if (key == AnthropicServerToolTypes.webSearch) {
          final emission = await _handleWebSearchEvent(rawEvent);
          assets.addAll(emission.assets);
          links.addAll(emission.links);
          continue;
        }

        if (key == AnthropicServerToolTypes.webFetch) {
          final emission = await _handleWebFetchEvent(rawEvent);
          assets.addAll(emission.assets);
          links.addAll(emission.links);
        }
      }
    }

    return ToolDeliverableEmission(assets: assets, links: links);
  }

  /// Returns a deep copy of all recorded tool events.
  Map<String, List<Map<String, Object?>>> buildToolMetadata() => {
    for (final entry in _toolEventLog.entries)
      if (entry.value.isNotEmpty) entry.key: copyEventList(entry.value),
  };

  /// Collects any new files that have appeared in the Files API since the
  /// tracker was created.
  Future<List<Part>> collectRecentFiles() => _collectNewRemoteFiles();

  void _recordToolEvent(String key, Map<String, Object?> event) {
    final toolKey = _normalizeToolKey(key, event['tool_name'] as String?);
    final bucket = _toolEventLog.putIfAbsent(
      toolKey,
      () => <Map<String, Object?>>[],
    );
    bucket.add(Map<String, Object?>.from(event));
  }

  String _normalizeToolKey(String? metadataKey, String? toolName) {
    if (toolName != null && toolName.isNotEmpty) return toolName;
    if (metadataKey != null && metadataKey.isNotEmpty) return metadataKey;
    return AnthropicServerToolTypes.codeExecution;
  }

  Future<List<Part>> _handleCodeExecutionEvent(
    Map<String, Object?> event,
  ) async {
    final type = event['type'] as String? ?? '';

    if (type == 'server_tool_use') {
      return const [];
    }

    if (type == 'server_tool_input_delta') {
      return const [];
    }

    if (type == 'server_tool_use_completed') {
      final files = await _collectNewRemoteFiles();
      return files;
    }

    if (type != 'tool_result') return const [];

    final assets = <Part>[];
    final raw = event['raw_content'];
    final content = (raw is Map<String, Object?> || raw is List)
        ? raw
        : event['content'];

    for (final image in _findBase64Images(content)) {
      if (_emittedImageHashes.add(image.base64)) {
        assets.add(_decodeInlineImage(image));
      }
    }

    final fileRefs = _findFileRefs(content);
    for (final ref in fileRefs) {
      if (!_downloadedFileIds.add(ref.fileId)) continue;
      final downloaded = await _filesClient.download(ref.fileId);
      final inferredMime = ref.mimeType ?? downloaded.mimeType;
      final name = ref.filename ?? downloaded.filename;
      final extension = name == null && inferredMime != null
          ? Part.extensionFromMimeType(inferredMime)
          : null;
      final resolvedName =
          name ?? _composeFileName('anthropic_file_', ref.fileId, extension);

      assets.add(
        DataPart(
          downloaded.bytes,
          mimeType: inferredMime ?? 'application/octet-stream',
          name: resolvedName,
        ),
      );
    }

    return assets;
  }

  Future<ToolDeliverableEmission> _handleWebSearchEvent(
    Map<String, Object?> event,
  ) async {
    final type = event['type'] as String? ?? '';
    if (type != 'web_search_tool_result') {
      return const ToolDeliverableEmission();
    }

    final links = <LinkPart>[];
    final content = event['content'];
    if (content is List) {
      for (final item in content) {
        if (item is! Map<String, Object?>) continue;
        final url = item['url'] as String?;
        if (url == null || url.isEmpty) continue;
        final uri = Uri.tryParse(url);
        if (uri == null) continue;
        final normalized = uri.toString();
        if (!_seenSearchUrls.add(normalized)) continue;
        final title = item['title'] as String?;
        links.add(LinkPart(uri, name: title, mimeType: _extractMimeType(item)));
      }
    }

    return ToolDeliverableEmission(links: links);
  }

  Future<ToolDeliverableEmission> _handleWebFetchEvent(
    Map<String, Object?> event,
  ) async {
    final type = event['type'] as String? ?? '';
    if (type != 'web_fetch_tool_result') {
      return const ToolDeliverableEmission();
    }

    final toolUseId = event['tool_use_id'] as String? ?? '';
    final dedupeKey = '$type:$toolUseId';
    if (!_processedFetchEvents.add(dedupeKey)) {
      return const ToolDeliverableEmission();
    }

    final assets = <Part>[];
    final links = <LinkPart>[];

    final content = event['content'];
    if (content is Map<String, Object?>) {
      final urlString = content['url'] as String?;
      if (urlString != null && urlString.isNotEmpty) {
        final uri = Uri.tryParse(urlString);
        if (uri != null) {
          final normalized = uri.toString();
          if (_seenFetchUrls.add(normalized)) {
            final innerContent = content['content'];
            final title = innerContent is Map<String, Object?>
                ? innerContent['title'] as String?
                : null;
            links.add(
              LinkPart(uri, mimeType: _extractMimeType(content), name: title),
            );
          }
        }
      }

      final inner = content['content'];
      if (inner is Map<String, Object?>) {
        final source =
            (inner['content'] as Map<String, Object?>?) ??
            (inner['source'] as Map<String, Object?>?);
        if (source != null) {
          final sourceType = source['type'] as String?;
          final data = source['data'] as String?;
          final mediaType = _extractMediaType(source);

          if (data != null && data.isNotEmpty) {
            Uint8List? bytes;
            if (sourceType == 'text' || sourceType == null) {
              bytes = Uint8List.fromList(utf8.encode(data));
            } else if (sourceType == 'base64' || sourceType == 'bytes') {
              bytes = base64Decode(data);
            }

            if (bytes != null) {
              final resolvedMime = mediaType ?? 'text/plain';
              final extension = Part.extensionFromMimeType(resolvedMime);
              final title = inner['title'] as String?;
              final baseName = title != null && title.trim().isNotEmpty
                  ? _sanitizeFileName(title)
                  : _composeFileName(
                      'web_fetch_document_',
                      (_webFetchDocumentCounter++).toString(),
                      extension,
                    );

              assets.add(
                DataPart(bytes, mimeType: resolvedMime, name: baseName),
              );
            }
          }
        }
      }
    }

    return ToolDeliverableEmission(assets: assets, links: links);
  }

  Iterable<_FileRef> _findFileRefs(Object? node) sync* {
    if (node is Map<String, Object?>) {
      final fileId = node['file_id'];
      if (fileId is String && fileId.isNotEmpty) {
        yield _FileRef(
          fileId: fileId,
          filename: node['filename'] as String?,
          mimeType: _extractMimeType(node),
        );
      }
      for (final value in node.values) {
        yield* _findFileRefs(value);
      }
      return;
    }

    if (node is List) {
      for (final value in node) {
        yield* _findFileRefs(value);
      }
    }
  }

  Iterable<_InlineImage> _findBase64Images(Object? node) sync* {
    if (node is Map<String, Object?>) {
      final base64 = node['image_base64'];
      if (base64 is String && base64.isNotEmpty) {
        yield _InlineImage(
          base64: base64,
          mimeType: _extractMimeType(node),
          filename: node['filename'] as String?,
        );
      }
      for (final value in node.values) {
        yield* _findBase64Images(value);
      }
      return;
    }

    if (node is List) {
      for (final value in node) {
        yield* _findBase64Images(value);
      }
    }
  }

  Future<List<Part>> _collectNewRemoteFiles({int attempt = 0}) async {
    final remoteFiles = await _filesClient.list(limit: 200);
    final newFiles =
        remoteFiles.where((file) {
          if (_seenRemoteFileIds.contains(file.id)) return false;
          if (file.createdAt == null) return true;
          return !file.createdAt!.isBefore(_startTime);
        }).toList()..sort((a, b) {
          final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return aTime.compareTo(bTime);
        });

    final assets = <Part>[];
    if (newFiles.isNotEmpty) {
      _logger.fine(
        'Detected ${newFiles.length} new Anthropic files after tool run '
        'starting at $_startTime.',
      );
    }
    for (final file in newFiles) {
      _seenRemoteFileIds.add(file.id);
      if (!_shouldDownload(file)) {
        continue;
      }
      if (!_downloadedFileIds.add(file.id)) {
        continue;
      }
      final downloaded = await _filesClient.download(file.id);
      final inferredMime = downloaded.mimeType ?? file.mimeType;
      final name =
          downloaded.filename ??
          file.filename ??
          _composeFileName(
            'anthropic_file_',
            file.id,
            _extensionFromMime(inferredMime),
          );
      _logger.fine(
        'Downloading Anthropic file ${file.id} ($name, mime=$inferredMime)',
      );
      assets.add(
        DataPart(
          downloaded.bytes,
          mimeType: inferredMime ?? 'application/octet-stream',
          name: name,
        ),
      );
    }

    if (assets.isEmpty && attempt < 3) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return _collectNewRemoteFiles(attempt: attempt + 1);
    }

    return assets;
  }

  bool _shouldDownload(AnthropicRemoteFile file) {
    if (file.mimeType == null || file.mimeType!.isEmpty) {
      return true;
    }
    final mime = file.mimeType!;
    for (final target in _targetMimeTypes) {
      if (target == '*/*') return true;
      if (target == 'image/*' && mime.startsWith('image/')) return true;
      if (target == 'text/*' && mime.startsWith('text/')) return true;
      if (target == mime) return true;
      if (target.startsWith('text/') && mime.startsWith('text/')) return true;
    }
    return false;
  }

  String? _extensionFromMime(String? mime) {
    if (mime == null) return null;
    return Part.extensionFromMimeType(mime);
  }

  String _sanitizeFileName(String name) =>
      name.replaceAll(RegExp(r'[\\/:]'), '_');

  DataPart _decodeInlineImage(_InlineImage ref) {
    final bytes = base64Decode(ref.base64);
    final inferredMime =
        ref.mimeType ?? lookupMimeType('image.bin', headerBytes: bytes);
    final extension = inferredMime == null
        ? null
        : Part.extensionFromMimeType(inferredMime);
    final baseName =
        ref.filename ??
        _composeFileName(
          'inline_image_',
          (_inlineImageCounter++).toString(),
          extension,
        );

    return DataPart(
      bytes,
      mimeType: inferredMime ?? 'image/png',
      name: baseName,
    );
  }

  String _composeFileName(String prefix, String id, String? extension) =>
      extension == null ? '$prefix$id' : '$prefix$id.$extension';
}

/// Container for deliverables emitted while processing tool metadata.
class ToolDeliverableEmission {
  /// Creates a new emission container.
  const ToolDeliverableEmission({
    this.assets = const <Part>[],
    this.links = const <LinkPart>[],
  });

  /// Binary assets produced by tool events (for example downloaded files).
  final List<Part> assets;

  /// External links discovered from tool events (for example search results).
  final List<LinkPart> links;
}

class _FileRef {
  const _FileRef({required this.fileId, this.filename, this.mimeType});

  final String fileId;
  final String? filename;
  final String? mimeType;
}

class _InlineImage {
  const _InlineImage({required this.base64, this.mimeType, this.filename});

  final String base64;
  final String? mimeType;
  final String? filename;
}

/// Creates a deep copy of a list of tool events.
List<Map<String, Object?>> copyEventList(List<Map<String, Object?>> source) =>
    source.map(Map<String, Object?>.from).toList();

/// Extracts a MIME type from a map, checking both snake_case and camelCase
/// keys.
String? _extractMimeType(Map<String, Object?> map) =>
    map['mime_type'] as String? ?? map['mimeType'] as String?;

/// Extracts a media type from a map, checking both snake_case and camelCase
/// keys.
String? _extractMediaType(Map<String, Object?> map) =>
    map['media_type'] as String? ?? map['mediaType'] as String?;
