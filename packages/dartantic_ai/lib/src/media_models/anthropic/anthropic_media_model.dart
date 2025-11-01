import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../chat_models/anthropic_chat/anthropic_chat_model.dart';
import '../../chat_models/anthropic_chat/anthropic_chat_options.dart';
import '../../retry_http_client.dart';
import 'anthropic_media_model_options.dart';

/// Media generation model backed by the Anthropic code execution tool.
class AnthropicMediaModel
    extends MediaGenerationModel<AnthropicMediaModelOptions> {
  /// Creates a new Anthropic media model instance.
  AnthropicMediaModel({
    required super.name,
    required super.defaultOptions,
    required AnthropicChatModel chatModel,
    required String apiKey,
    Uri? baseUrl,
    http.Client? httpClient,
    List<String> betaFeatures = const [],
  }) : _chatModel = chatModel,
       _filesClient = _AnthropicFilesClient(
         apiKey: apiKey,
         betaFeatures: betaFeatures,
         baseUrl: baseUrl,
         client: httpClient,
       );

  static final Logger _logger = Logger('dartantic.media.models.anthropic');

  static const AnthropicServerToolConfig _codeExecutionTool =
      AnthropicServerToolConfig(
        type: 'code_execution_20250825',
        name: 'code_execution',
      );

  final AnthropicChatModel _chatModel;
  final _AnthropicFilesClient _filesClient;

  /// Builds chat model options for provided media defaults.
  static AnthropicChatOptions buildChatOptions(
    AnthropicMediaModelOptions base,
  ) {
    final resolved = _resolve(base, null);
    return _toChatOptions(resolved);
  }

  @override
  Stream<MediaGenerationResult> generateMediaStream(
    String prompt, {
    required List<String> mimeTypes,
    List<ChatMessage> history = const [],
    List<Part> attachments = const [],
    AnthropicMediaModelOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    if (outputSchema != null) {
      throw UnsupportedError(
        'Anthropic media generation does not support output schemas.',
      );
    }

    if (mimeTypes.isEmpty) {
      throw ArgumentError.value(
        mimeTypes,
        'mimeTypes',
        'At least one MIME type must be provided.',
      );
    }

    _validateMimeTypes(mimeTypes);

    _logger.info(
      'Starting Anthropic media generation with ${history.length} history '
      'messages and MIME types: ${mimeTypes.join(', ')}',
    );

    final resolved = _resolve(defaultOptions, options);
    final chatOptions = _toChatOptions(resolved);
    final tracker = _AnthropicMediaTracker(_filesClient);
    final augmentedPrompt = _augmentPrompt(prompt, mimeTypes);

    final messages = <ChatMessage>[
      ...history,
      ChatMessage.user(augmentedPrompt, parts: attachments),
    ];

    var chunkIndex = 0;
    await for (final chunk in _chatModel.sendStream(
      messages,
      options: chatOptions,
    )) {
      chunkIndex++;
      _logger.fine('Anthropic media chunk $chunkIndex received');
      final mapped = await _mapChunk(chunk, tracker, mimeTypes.toSet());
      yield mapped;
    }
  }

  @override
  void dispose() {
    _filesClient.close();
    _chatModel.dispose();
  }

  Future<MediaGenerationResult> _mapChunk(
    ChatResult<ChatMessage> result,
    _AnthropicMediaTracker tracker,
    Set<String> targetMimeTypes,
  ) async {
    _logger.fine('Processing Anthropic chunk for result id ${result.id}');
    if (result.metadata.isNotEmpty) {
      try {
        _logger.finer(
          'Anthropic chunk metadata: ${jsonEncode(result.metadata)}',
        );
      } on Object catch (_) {
        _logger.finer(
          'Anthropic chunk metadata contained non-serializable data',
        );
      }
    }
    final assets = <Part>[];
    final links = <LinkPart>[];
    final metadata = Map<String, dynamic>.from(result.metadata);

    assets.addAll(tracker.collectMessageAssets(result.messages));
    links.addAll(tracker.collectMessageLinks(result.messages));

    final metadataAssets = await tracker.handleMetadata(result.metadata);
    assets.addAll(metadataAssets);
    tracker.recordMessageText(result.messages);

    if (result.output.parts.isNotEmpty) {
      for (final part in result.output.parts) {
        if (part is TextPart) {
          final text = part.text.trim();
          if (text.isNotEmpty) tracker.recordTextSnippet(text);
        }
      }
    }

    final isComplete = result.finishReason != FinishReason.unspecified;

    if (isComplete &&
        assets.isEmpty &&
        targetMimeTypes.any((mime) => mime.contains('pdf'))) {
      _logger.fine(
        'Fallback PDF condition met. Summary tokens collected: '
        '${tracker.buildTextSummary().length}',
      );
      final summary = tracker.buildTextSummary();
      if (summary.isNotEmpty) {
        final fallbackPdf = await _buildFallbackPdf(summary);
        if (fallbackPdf != null) {
          assets.add(fallbackPdf);
          metadata['fallback'] = 'generated_pdf';
          _logger.warning(
            'Anthropic fallback PDF generated from summary text.',
          );
        }
      }
    }

    if (isComplete) {
      _logger.fine(
        'Anthropic media generation completed with ${assets.length} assets '
        'and ${links.length} links',
      );
    }

    return MediaGenerationResult(
      id: result.id,
      assets: assets,
      links: links,
      messages: result.messages,
      metadata: metadata,
      usage: result.usage,
      finishReason: result.finishReason,
      isComplete: isComplete,
    );
  }

  static _ResolvedAnthropicMediaSettings _resolve(
    AnthropicMediaModelOptions base,
    AnthropicMediaModelOptions? override,
  ) {
    final mergedServerTools = <AnthropicServerToolConfig>[
      ...?base.serverTools,
      ...?override?.serverTools,
    ];

    return _ResolvedAnthropicMediaSettings(
      maxTokens: override?.maxTokens ?? base.maxTokens,
      stopSequences: override?.stopSequences ?? base.stopSequences,
      temperature: override?.temperature ?? base.temperature,
      topK: override?.topK ?? base.topK,
      topP: override?.topP ?? base.topP,
      userId: override?.userId ?? base.userId,
      thinkingBudgetTokens:
          override?.thinkingBudgetTokens ?? base.thinkingBudgetTokens,
      serverTools: mergedServerTools,
    );
  }

  static AnthropicChatOptions _toChatOptions(
    _ResolvedAnthropicMediaSettings settings,
  ) {
    final toolMap = <String, AnthropicServerToolConfig>{
      _codeExecutionTool.name: _codeExecutionTool,
      for (final tool in settings.serverTools) tool.name: tool,
    };

    return AnthropicChatOptions(
      maxTokens: settings.maxTokens,
      stopSequences: settings.stopSequences,
      temperature: settings.temperature,
      topK: settings.topK,
      topP: settings.topP,
      userId: settings.userId,
      thinkingBudgetTokens: settings.thinkingBudgetTokens,
      serverTools: toolMap.values.toList(growable: false),
    );
  }

  void _validateMimeTypes(List<String> mimeTypes) {
    const supportedText = <String>{
      'application/pdf',
      'application/zip',
      'application/octet-stream',
      'text/plain',
      'text/markdown',
      'text/csv',
    };

    final unsupported = mimeTypes.where(
      (type) => !_isImageMimeType(type) && !supportedText.contains(type),
    );

    if (unsupported.isNotEmpty) {
      throw UnsupportedError(
        'Anthropic media generation does not support MIME types: '
        '${unsupported.join(', ')}. '
        'Supported values include image/*, image/png, image/jpeg, '
        'image/webp, and ${supportedText.join(', ')}.',
      );
    }
  }

  bool _isImageMimeType(String value) =>
      value == 'image/*' || value.startsWith('image/');

  String _augmentPrompt(String prompt, List<String> mimeTypes) {
    if (prompt.trim().isEmpty) return prompt;
    const guidance =
        '\n\nUse the available code execution tool to programmatically '
        'create the requested files. Create any helper scripts in the text '
        'editor tool, then execute them with the shell tool (for example, by '
        'running `python /tmp/create_file.py`) so the artifacts are actually '
        'produced. When a PDF is required, generate it with Python '
        '(installing libraries such as reportlab if needed), run the script '
        'to build the PDF, confirm the file exists, and then return it. For '
        'text artifacts, write the content to a file (e.g., using `cat` or '
        'Python) and return it as a downloadable asset before finishing.';
    if (prompt.contains('code execution tool')) return prompt;
    return '$prompt$guidance';
  }

  Future<DataPart?> _buildFallbackPdf(String content) async {
    if (content.isEmpty) return null;

    final document = pw.Document();
    document.addPage(
      pw.Page(
        build: (context) => pw.Padding(
          padding: const pw.EdgeInsets.all(36),
          child: pw.Text(content, style: const pw.TextStyle(fontSize: 14)),
        ),
      ),
    );

    final bytes = await document.save();
    return DataPart(bytes, mimeType: 'application/pdf', name: 'summary.pdf');
  }
}

class _ResolvedAnthropicMediaSettings {
  const _ResolvedAnthropicMediaSettings({
    required this.serverTools,
    this.maxTokens,
    this.stopSequences,
    this.temperature,
    this.topK,
    this.topP,
    this.userId,
    this.thinkingBudgetTokens,
  });

  final int? maxTokens;
  final List<String>? stopSequences;
  final double? temperature;
  final int? topK;
  final double? topP;
  final String? userId;
  final int? thinkingBudgetTokens;
  final List<AnthropicServerToolConfig> serverTools;
}

class _AnthropicMediaTracker {
  _AnthropicMediaTracker(this._filesClient);

  static final Logger _logger = Logger(
    'dartantic.media.models.anthropic.tracker',
  );

  final _AnthropicFilesClient _filesClient;
  final Set<String> _downloadedFileIds = <String>{};
  final Set<String> _emittedImageHashes = <String>{};
  int _inlineImageCounter = 0;
  String? _containerId;
  final List<String> _textSnippets = <String>[];

  List<Part> collectMessageAssets(List<ChatMessage> messages) {
    final assets = <Part>[];
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is DataPart) assets.add(part);
      }
    }
    return assets;
  }

  List<LinkPart> collectMessageLinks(List<ChatMessage> messages) {
    final links = <LinkPart>[];
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is LinkPart) links.add(part);
      }
    }
    return links;
  }

  void recordMessageText(List<ChatMessage> messages) {
    for (final message in messages) {
      for (final part in message.parts) {
        if (part is TextPart) {
          recordTextSnippet(part.text);
        }
      }
    }
  }

  void recordTextSnippet(String text) {
    final snippet = text.trim();
    if (snippet.isNotEmpty) _textSnippets.add(snippet);
  }

  String buildTextSummary() => _textSnippets.join('\n\n').trim();

  Future<List<Part>> handleMetadata(Map<String, dynamic> metadata) async {
    final containerId = metadata['container_id'];
    if (containerId is String && containerId.isNotEmpty) {
      _containerId = containerId;
      _logger.fine('Tracked Anthropic container id: $_containerId');
    }

    final rawEvents = metadata['code_execution'];
    if (rawEvents is! List) return const [];

    final assets = <Part>[];
    for (final event in rawEvents) {
      if (event is! Map<String, Object?>) continue;
      final type = event['type'] as String? ?? '';
      if (type == 'tool_result') {
        assets.addAll(await _handleToolResult(event));
      }
    }
    return assets;
  }

  Future<List<Part>> _handleToolResult(Map<String, Object?> event) async {
    try {
      _logger.finer(
        'Processing Anthropic code execution event: ${jsonEncode(event)}',
      );
    } on Object catch (_) {
      // Ignore JSON encoding issues in diagnostics.
    }

    final assets = <Part>[];
    final raw = event['raw_content'];
    final content = (raw is Map<String, Object?> || raw is List)
        ? raw
        : event['content'];

    for (final image in _findBase64Images(content)) {
      if (_emittedImageHashes.add(image.base64)) {
        assets.add(_decodeImage(image));
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

  Iterable<_AnthropicFileRef> _findFileRefs(Object? node) sync* {
    if (node is Map<String, Object?>) {
      final fileId = node['file_id'];
      if (fileId is String && fileId.isNotEmpty) {
        yield _AnthropicFileRef(
          fileId: fileId,
          filename: node['filename'] as String?,
          mimeType: node['mime_type'] as String? ?? node['mimeType'] as String?,
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

  Iterable<_AnthropicInlineImage> _findBase64Images(Object? node) sync* {
    if (node is Map<String, Object?>) {
      final base64 = node['image_base64'];
      if (base64 is String && base64.isNotEmpty) {
        yield _AnthropicInlineImage(
          base64: base64,
          mimeType: node['mime_type'] as String? ?? node['mimeType'] as String?,
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

  Part _decodeImage(_AnthropicInlineImage ref) {
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
}

class _AnthropicFileRef {
  const _AnthropicFileRef({required this.fileId, this.filename, this.mimeType});

  final String fileId;
  final String? filename;
  final String? mimeType;
}

class _AnthropicInlineImage {
  const _AnthropicInlineImage({
    required this.base64,
    this.mimeType,
    this.filename,
  });

  final String base64;
  final String? mimeType;
  final String? filename;
}

class _AnthropicFilesClient {
  _AnthropicFilesClient({
    required this.apiKey,
    required List<String> betaFeatures,
    Uri? baseUrl,
    http.Client? client,
  }) : _betaHeader = _composeBetaHeader(betaFeatures),
       _baseUri = baseUrl ?? Uri.parse('https://api.anthropic.com/'),
       _client = client ?? RetryHttpClient(inner: http.Client());

  final String apiKey;
  final String _betaHeader;
  final Uri _baseUri;
  final http.Client _client;

  static String _composeBetaHeader(List<String> features) {
    final betaFlags = <String>{
      'files-api-2025-04-14',
      'code-execution-2025-08-25',
      ...features,
    };
    return betaFlags.join(',');
  }

  Future<_DownloadedAnthropicFile> download(String fileId) async {
    final metadata = await _metadata(fileId);
    final bytes = await _contentBytes(fileId);
    return _DownloadedAnthropicFile(
      bytes: bytes,
      filename: metadata.filename,
      mimeType: metadata.mimeType,
    );
  }

  Future<_AnthropicFileMetadata> _metadata(String fileId) async {
    final uri = _baseUri.resolve('/v1/files/$fileId?beta=true');
    final response = await _client.get(
      uri,
      headers: _headers(accept: 'application/json'),
    );

    if (response.statusCode != 200) {
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
    final uri = _baseUri.resolve('/v1/files/$fileId/content?beta=true');
    final response = await _client.get(
      uri,
      headers: _headers(accept: 'application/octet-stream'),
    );

    if (response.statusCode != 200) {
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
  };

  void close() {
    _client.close();
  }
}

class _AnthropicFileMetadata {
  const _AnthropicFileMetadata({this.filename, this.mimeType});

  final String? filename;
  final String? mimeType;
}

class _DownloadedAnthropicFile {
  const _DownloadedAnthropicFile({
    required this.bytes,
    this.filename,
    this.mimeType,
  });

  final Uint8List bytes;
  final String? filename;
  final String? mimeType;
}

String _composeFileName(String prefix, String id, String? extension) =>
    extension == null ? '$prefix$id' : '$prefix$id.$extension';
