// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:sse_channel/sse_channel.dart';

import '../../custom_http_client.dart';
import '../../providers/google_api_utils.dart';

/// Lightweight client for interacting with the Google Gemini media streaming
/// endpoint.
class GoogleImageGenerationClient {
  GoogleImageGenerationClient({
    required String apiKey,
    required Uri baseUrl,
    http.Client? httpClient,
  }) : _httpClient = CustomHttpClient(
         baseHttpClient: httpClient ?? http.Client(),
         baseUrl: baseUrl,
         headers: {'X-Goog-Api-Key': apiKey},
         queryParams: const {},
       );

  final http.Client _httpClient;

  static final _logger = Logger('dartantic.media.google.image.generation');

  /// Streams content from the Gemini `streamGenerateContent` endpoint.
  Stream<GoogleMediaChunk> streamGenerateContent(
    GoogleMediaGenerationRequest request,
  ) async* {
    final uri = _buildStreamUri(request.model);

    final httpRequest = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(request.body);

    final response = await _httpClient.send(httpRequest);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw http.ClientException(
        'Google media stream failed with status '
        '${response.statusCode}: $body',
        uri,
      );
    }

    final transformer = SseTransformer();
    yield* response.stream
        .transform(transformer)
        .map((event) => event.data)
        .where((data) => data != null && data.isNotEmpty)
        .map((data) => jsonDecode(data!) as Map<String, dynamic>)
        .map(GoogleMediaChunk.fromJson);
  }

  Uri _buildStreamUri(String model) {
    final normalized = normalizeGoogleModelName(model);

    final base = (_httpClient as CustomHttpClient).baseUrl;
    final normalizedPath = normalized.startsWith('models/')
        ? normalized.substring('models/'.length)
        : normalized;

    var basePath = base.path.endsWith('/') || base.path.isEmpty
        ? base.path
        : '${base.path}/';
    if (basePath.isEmpty) basePath = '/';
    final fullPath = '${basePath}models/$normalizedPath:streamGenerateContent';

    _logger.fine('Full path: $fullPath');

    final resolvedPath = fullPath.startsWith('/') ? fullPath : '/$fullPath';

    return base.replace(
      path: resolvedPath,
      queryParameters: const {'alt': 'sse'},
    );
  }
}

/// Request payload for the Gemini streaming endpoint.
class GoogleMediaGenerationRequest {
  GoogleMediaGenerationRequest({
    required this.model,
    required this.contents,
    this.generationConfig,
    this.safetySettings,
  });

  final String model;
  final List<Map<String, Object?>> contents;
  final Map<String, Object?>? generationConfig;
  final List<Map<String, Object?>>? safetySettings;

  Map<String, Object?> get body => {
    'contents': contents,
    if (generationConfig != null) 'generationConfig': generationConfig,
    if (safetySettings != null && safetySettings!.isNotEmpty)
      'safetySettings': safetySettings,
  };
}

/// Normalised chunk emitted by the Gemini streaming endpoint.
class GoogleMediaChunk {
  GoogleMediaChunk({
    required this.id,
    required this.assets,
    required this.messages,
    required this.metadata,
    required this.finishReason,
    required this.isComplete,
    this.usage,
  });

  factory GoogleMediaChunk.fromJson(Map<String, dynamic> json) {
    final candidates = (json['candidates'] as List?) ?? const [];
    final firstCandidate = candidates.isNotEmpty
        ? candidates.first as Map<String, dynamic>
        : null;

    final content =
        firstCandidate?['content'] as Map<String, dynamic>? ?? const {};
    final parts = (content['parts'] as List?) ?? const [];
    final role = content['role'] as String? ?? 'model';

    final assets = <GoogleMediaInlineAsset>[];
    final messages = <GoogleMediaMessage>[];

    final textParts = <String>[];
    for (final part in parts.cast<Map<String, dynamic>>()) {
      if (part.containsKey('text')) {
        textParts.add(part['text'] as String);
      } else if (part.containsKey('inlineData')) {
        final inlineData = part['inlineData'] as Map<String, dynamic>;
        final mimeType =
            inlineData['mimeType'] as String? ?? 'application/octet-stream';
        final data = inlineData['data'] as String? ?? '';
        assets.add(
          GoogleMediaInlineAsset(
            name: inlineData['fileUri'] as String?,
            mimeType: mimeType,
            data: data,
          ),
        );
      }
    }

    if (textParts.isNotEmpty) {
      messages.add(GoogleMediaMessage(role: role, text: textParts.join()));
    }

    final finishReason = firstCandidate?['finishReason'] as String?;
    final responseId = json['responseId'] as String? ?? '';
    final usage = json['usageMetadata'] as Map<String, dynamic>?;

    final metadata = <String, Object?>{
      if (json['modelVersion'] != null) 'model_version': json['modelVersion'],
      if (firstCandidate?['safetyRatings'] != null)
        'safety_ratings': firstCandidate!['safetyRatings'],
      if (json['promptFeedback'] != null)
        'prompt_feedback': json['promptFeedback'],
      if (responseId.isNotEmpty) 'response_id': responseId,
    };

    return GoogleMediaChunk(
      id: responseId,
      assets: assets,
      messages: messages,
      metadata: metadata,
      finishReason: finishReason,
      isComplete:
          finishReason != null && finishReason != 'FINISH_REASON_UNSPECIFIED',
      usage: usage == null ? null : GoogleMediaUsage.fromJson(usage),
    );
  }

  final String id;
  final List<GoogleMediaInlineAsset> assets;
  final List<GoogleMediaMessage> messages;
  final Map<String, Object?> metadata;
  final String? finishReason;
  final bool isComplete;
  final GoogleMediaUsage? usage;
}

class GoogleMediaInlineAsset {
  const GoogleMediaInlineAsset({
    required this.mimeType,
    required this.data,
    this.name,
  });

  final String? name;
  final String mimeType;
  final String data;
}

class GoogleMediaMessage {
  const GoogleMediaMessage({required this.role, required this.text});

  final String role;
  final String text;
}

class GoogleMediaUsage {
  const GoogleMediaUsage({
    this.promptTokens,
    this.candidatesTokens,
    this.totalTokens,
  });

  factory GoogleMediaUsage.fromJson(Map<String, dynamic> json) =>
      GoogleMediaUsage(
        promptTokens: json['promptTokenCount'] as int?,
        candidatesTokens: json['candidatesTokenCount'] as int?,
        totalTokens: json['totalTokenCount'] as int?,
      );

  final int? promptTokens;
  final int? candidatesTokens;
  final int? totalTokens;
}
