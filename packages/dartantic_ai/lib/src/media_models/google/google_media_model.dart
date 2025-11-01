import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:google_cloud_ai_generativelanguage_v1beta/generativelanguage.dart'
    as gl;
import 'package:google_cloud_protobuf/protobuf.dart' as gpb;
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../../chat_models/google_chat/google_message_mappers.dart';
import '../../custom_http_client.dart';
import '../../providers/google_api_utils.dart';
import '../../retry_http_client.dart';
import 'google_media_model_options.dart';

/// Signature for streaming Gemini media generation responses.
typedef GoogleMediaStreamHandler =
    Stream<gl.GenerateContentResponse> Function(
      gl.GenerateContentRequest request,
    );

/// Media generation model for Google Gemini.
class GoogleMediaModel extends MediaGenerationModel<GoogleMediaModelOptions> {
  /// Creates a new Google media model instance.
  GoogleMediaModel({
    required super.name,
    required String apiKey,
    required Uri baseUrl,
    GoogleMediaModelOptions? defaultOptions,
    http.Client? client,
    GoogleMediaStreamHandler? streamHandler,
    gl.PredictionService? predictionService,
  }) : super(
         defaultOptions: defaultOptions ?? const GoogleMediaModelOptions(),
       ) {
    if (streamHandler != null) {
      _streamHandler = streamHandler;
      _service = null;
      _predictionService = predictionService;
    } else {
      final httpClient = CustomHttpClient(
        baseHttpClient: client ?? RetryHttpClient(inner: http.Client()),
        baseUrl: baseUrl,
        headers: {'x-goog-api-key': apiKey},
        queryParams: const {},
      );
      final service = gl.GenerativeService(client: httpClient);
      _service = service;
      _predictionService =
          predictionService ??
          gl.PredictionService(
            client: CustomHttpClient(
              baseHttpClient: RetryHttpClient(inner: http.Client()),
              baseUrl: baseUrl,
              headers: {'x-goog-api-key': apiKey},
              queryParams: const {},
            ),
          );
      _streamHandler = service.streamGenerateContent;
    }
  }

  static final Logger _logger = Logger('dartantic.media.google');

  static const String _defaultImagenModel = 'models/imagen-3.0-generate-002';

  gl.GenerativeService? _service;
  gl.PredictionService? _predictionService;
  late final GoogleMediaStreamHandler _streamHandler;

  @override
  Stream<MediaGenerationResult> generateMediaStream(
    String prompt, {
    required List<String> mimeTypes,
    List<ChatMessage> history = const [],
    List<Part> attachments = const [],
    GoogleMediaModelOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    if (outputSchema != null) {
      throw UnsupportedError(
        'Google media generation does not support output schemas.',
      );
    }
    final resolvedOptions = options ?? defaultOptions;
    final resolvedMimeType = _resolveMimeType(
      mimeTypes,
      resolvedOptions.responseMimeType ?? defaultOptions.responseMimeType,
    );

    final messages = <ChatMessage>[
      ...history,
      ChatMessage.user(prompt, parts: attachments),
    ];

    if (_isImageMime(resolvedMimeType)) {
      if (attachments.isNotEmpty) {
        throw UnsupportedError(
          'Google image generation does not support attachments.',
        );
      }
      await for (final chunk in _generateImagenStream(
        messages,
        mimeType: resolvedMimeType,
        options: resolvedOptions,
      )) {
        yield chunk;
      }
      return;
    }

    final contents = messages.toContentList();
    if (contents.isEmpty) {
      throw ArgumentError(
        'Media generation requires a non-empty prompt or attachments.',
      );
    }

    final request = gl.GenerateContentRequest(
      model: normalizeGoogleModelName(name),
      contents: contents,
      generationConfig: _buildGenerationConfig(
        resolvedOptions,
        resolvedMimeType,
      ),
      safetySettings:
          (resolvedOptions.safetySettings ?? defaultOptions.safetySettings)
              ?.toSafetySettings(),
    );

    var chunkIndex = 0;
    await for (final response in _streamHandler(request)) {
      chunkIndex++;
      _logger.fine(
        'Received Google media chunk $chunkIndex for model: ${request.model}',
      );
      yield _mapResponse(response, resolvedMimeType);
    }
  }

  gl.GenerationConfig _buildGenerationConfig(
    GoogleMediaModelOptions options,
    String? responseMimeType,
  ) {
    const allowedTextResponseTypes = <String>{
      'text/plain',
      'application/json',
      'application/xml',
      'application/yaml',
      'text/x.enum',
    };

    final normalizedMime = responseMimeType ?? options.responseMimeType;
    final isImageMime =
        normalizedMime != null && normalizedMime.startsWith('image/');
    final resolvedMime = normalizedMime == null
        ? null
        : isImageMime
        ? normalizedMime
        : allowedTextResponseTypes.contains(normalizedMime)
        ? normalizedMime
        : null;

    return gl.GenerationConfig(
      temperature: options.temperature,
      topP: options.topP,
      topK: options.topK,
      maxOutputTokens: options.maxOutputTokens,
      responseMimeType: isImageMime ? null : resolvedMime,
      responseModalities: null,
      imageConfig: isImageMime ? gl.ImageConfig() : null,
      mediaResolution: isImageMime
          ? gl.GenerationConfig_MediaResolution.mediaResolutionHigh
          : null,
    );
  }

  MediaGenerationResult _mapResponse(
    gl.GenerateContentResponse response,
    String mimeType,
  ) {
    final assets = <Part>[];
    final links = <LinkPart>[];
    final messages = <ChatMessage>[];
    final metadata = <String, dynamic>{
      if (response.modelVersion != null) 'model_version': response.modelVersion,
      if (response.responseId != null) 'response_id': response.responseId,
    };
    var finishReasonEnum = FinishReason.unspecified;
    var isComplete = false;

    final candidates = response.candidates ?? const <gl.Candidate>[];
    if (candidates.isNotEmpty) {
      final candidate = candidates.first;
      final candidateParts = candidate.content?.parts ?? const <gl.Part>[];
      final textParts = <Part>[];

      for (final part in candidateParts) {
        final text = part.text;
        if (text != null && text.isNotEmpty) {
          textParts.add(TextPart(text));
        }

        final inlineData = part.inlineData;
        if (inlineData?.data != null) {
          assets.add(
            DataPart(
              inlineData!.data!,
              mimeType: inlineData.mimeType ?? mimeType,
            ),
          );
        }

        final fileData = part.fileData;
        if (fileData?.fileUri != null) {
          links.add(
            LinkPart(
              Uri.parse(fileData!.fileUri!),
              mimeType: fileData.mimeType,
            ),
          );
        }
      }

      if (textParts.isNotEmpty) {
        messages.add(
          ChatMessage(role: ChatMessageRole.model, parts: textParts),
        );
      }

      final finishReasonProto = candidate.finishReason;
      if (finishReasonProto != null) {
        metadata['finish_reason'] = finishReasonProto.value;
      }
      if (candidate.finishMessage != null &&
          candidate.finishMessage!.isNotEmpty) {
        metadata['finish_message'] = candidate.finishMessage;
      }

      final safetyRatings = candidate.safetyRatings
          ?.map(
            (rating) => {
              'category': rating.category?.value,
              'probability': rating.probability?.value,
            },
          )
          .toList(growable: false);
      if (safetyRatings != null && safetyRatings.isNotEmpty) {
        metadata['safety_ratings'] = safetyRatings;
      }

      final promptFeedback = response.promptFeedback;
      if (promptFeedback?.blockReason != null) {
        metadata['prompt_block_reason'] = promptFeedback!.blockReason!.value;
      }
      final promptSafety = promptFeedback?.safetyRatings
          ?.map(
            (rating) => {
              'category': rating.category?.value,
              'probability': rating.probability?.value,
            },
          )
          .toList(growable: false);
      if (promptSafety != null && promptSafety.isNotEmpty) {
        metadata['prompt_safety_ratings'] = promptSafety;
      }

      final reasonProto = candidate.finishReason;
      finishReasonEnum = _mapFinishReason(reasonProto);
      isComplete = _isComplete(candidate);
      if (reasonProto != null &&
          reasonProto != gl.Candidate_FinishReason.finishReasonUnspecified) {
        metadata['finish_reason_proto'] = reasonProto.value;
      }
    }

    return MediaGenerationResult(
      id: response.responseId ?? '',
      assets: assets,
      links: links,
      messages: messages,
      metadata: metadata,
      usage: _mapUsage(response.usageMetadata),
      finishReason: finishReasonEnum,
      isComplete: isComplete,
    );
  }

  Stream<MediaGenerationResult> _generateImagenStream(
    List<ChatMessage> messages, {
    required String mimeType,
    required GoogleMediaModelOptions options,
  }) async* {
    final predictionService = _predictionService;
    if (predictionService == null) {
      throw StateError(
        'Google media prediction service is not initialized for image '
        'generation.',
      );
    }

    final prompt = _composeImagenPrompt(messages);
    if (prompt.isEmpty) {
      throw ArgumentError(
        'Google image generation requires a non-empty textual prompt.',
      );
    }
    final sanitizedPrompt = _sanitizeImagenPrompt(prompt);

    final parameters = _buildImagenParameters(options, mimeType);
    final request = gl.PredictRequest(
      model: options.imagenModel ?? _defaultImagenModel,
      instances: [
        gpb.Value.fromJson({'prompt': sanitizedPrompt}),
      ],
      parameters: gpb.Value.fromJson(parameters),
    );

    _logger.fine(
      'Submitting Imagen predict request to ${request.model} '
      'with mimeType $mimeType and parameters: $parameters',
    );

    final response = await predictionService.predict(request);
    final (assets, metadata) = _parseImagenResponse(response, mimeType);

    if (assets.isEmpty) {
      final filteredReason = metadata['rai_filtered_reason'];
      if (filteredReason != null) {
        throw StateError(
          'Google image generation request was filtered: $filteredReason',
        );
      }
      throw StateError('Google image generation returned no assets.');
    }

    yield MediaGenerationResult(
      id: '',
      assets: assets,
      metadata: metadata,
      messages: [
        ChatMessage(
          role: ChatMessageRole.model,
          parts: [TextPart('Generated ${assets.length} image(s).')],
        ),
      ],
      isComplete: true,
      finishReason: FinishReason.stop,
    );
  }

  Map<String, Object?> _buildImagenParameters(
    GoogleMediaModelOptions options,
    String mimeType,
  ) {
    final sampleCount =
        options.imageSampleCount != null && options.imageSampleCount! > 0
        ? options.imageSampleCount!
        : 1;
    final params = <String, Object?>{
      'sampleCount': sampleCount,
      'outputOption': {'mimeType': mimeType},
      'includeRaiReason': true,
      'includeSafetyAttributes': true,
    };

    if (options.aspectRatio != null && options.aspectRatio!.isNotEmpty) {
      params['aspectRatio'] = options.aspectRatio;
    }
    if (options.negativePrompt != null && options.negativePrompt!.isNotEmpty) {
      params['negativePrompt'] = options.negativePrompt;
    }
    if (options.addWatermark != null) {
      params['addWatermark'] = options.addWatermark;
    }

    return params;
  }

  (List<Part> assets, Map<String, dynamic> metadata) _parseImagenResponse(
    gl.PredictResponse response,
    String fallbackMime,
  ) {
    final assets = <Part>[];
    final metadata = <String, dynamic>{'model': _defaultImagenModel};

    final predictions = response.predictions ?? const <gpb.Value>[];
    metadata['prediction_count'] = predictions.length;

    var index = 0;
    for (final value in predictions) {
      final json = value.toJson();
      if (json is! Map) continue;

      final raiReason = json['raiFilteredReason'];
      if (raiReason is String && raiReason.isNotEmpty) {
        metadata['rai_filtered_reason'] = raiReason;
        continue;
      }

      final base64 = json['bytesBase64Encoded'];
      if (base64 is! String || base64.isEmpty) continue;

      final mime = (json['mimeType'] as String?) ?? fallbackMime;
      final extension = Part.extensionFromMimeType(mime);
      final nameSuffix = extension == null ? '' : '.$extension';
      final assetName = 'image_${index++}$nameSuffix';
      final bytes = base64Decode(base64);

      assets.add(DataPart(bytes, mimeType: mime, name: assetName));
    }

    return (assets, metadata);
  }

  String _composeImagenPrompt(List<ChatMessage> messages) {
    if (messages.isEmpty) return '';
    final buffer = StringBuffer();
    for (final message in messages) {
      final text = message.parts
          .whereType<TextPart>()
          .map((part) => part.text.trim())
          .where((text) => text.isNotEmpty)
          .join(' ');
      if (text.isEmpty) continue;
      final roleLabel = switch (message.role) {
        ChatMessageRole.user => 'User',
        ChatMessageRole.model => 'Model',
        _ => message.role.name,
      };
      buffer.writeln('$roleLabel: $text');
    }
    return buffer.toString().trim();
  }

  String _sanitizeImagenPrompt(String prompt) {
    if (prompt.isEmpty) return prompt;
    return '$prompt\n\nGenerate a brand-neutral, generic image suitable for '
        'all audiences.';
  }

  LanguageModelUsage? _mapUsage(
    gl.GenerateContentResponse_UsageMetadata? usage,
  ) {
    if (usage == null) return null;
    return LanguageModelUsage(
      promptTokens: usage.promptTokenCount,
      responseTokens: usage.candidatesTokenCount,
      totalTokens: usage.totalTokenCount,
    );
  }

  bool _isComplete(gl.Candidate candidate) {
    final reason = candidate.finishReason;
    return reason != null &&
        reason != gl.Candidate_FinishReason.finishReasonUnspecified;
  }

  FinishReason _mapFinishReason(gl.Candidate_FinishReason? reason) {
    if (reason == null ||
        reason == gl.Candidate_FinishReason.finishReasonUnspecified) {
      return FinishReason.unspecified;
    }
    if (reason == gl.Candidate_FinishReason.stop) {
      return FinishReason.stop;
    }
    if (reason == gl.Candidate_FinishReason.maxTokens) {
      return FinishReason.length;
    }
    if (reason == gl.Candidate_FinishReason.recitation) {
      return FinishReason.recitation;
    }
    if (reason == gl.Candidate_FinishReason.unexpectedToolCall ||
        reason == gl.Candidate_FinishReason.tooManyToolCalls ||
        reason == gl.Candidate_FinishReason.malformedFunctionCall) {
      return FinishReason.toolCalls;
    }
    if (reason == gl.Candidate_FinishReason.noImage ||
        reason == gl.Candidate_FinishReason.imageOther ||
        reason == gl.Candidate_FinishReason.other) {
      return FinishReason.unspecified;
    }
    if (reason == gl.Candidate_FinishReason.safety ||
        reason == gl.Candidate_FinishReason.prohibitedContent ||
        reason == gl.Candidate_FinishReason.language ||
        reason == gl.Candidate_FinishReason.blocklist ||
        reason == gl.Candidate_FinishReason.imageSafety ||
        reason == gl.Candidate_FinishReason.imageProhibitedContent ||
        reason == gl.Candidate_FinishReason.imageRecitation ||
        reason == gl.Candidate_FinishReason.spii) {
      return FinishReason.contentFilter;
    }
    return FinishReason.unspecified;
  }

  String _resolveMimeType(List<String> requested, String? overrideMime) {
    const supported = <String>{'image/png', 'image/jpeg', 'image/webp'};

    if (overrideMime != null && supported.contains(overrideMime)) {
      return overrideMime;
    }

    for (final candidate in requested) {
      if (candidate == 'image/*') return 'image/png';
      if (supported.contains(candidate)) return candidate;
    }

    if (overrideMime != null) {
      throw UnsupportedError(
        'Google media generation does not support MIME type "$overrideMime". '
        'Supported values: ${supported.join(', ')}.',
      );
    }

    throw UnsupportedError(
      'Google media generation supports only ${supported.join(', ')}. '
      'Requested: ${requested.join(', ')}',
    );
  }

  bool _isImageMime(String mimeType) => mimeType.startsWith('image/');

  @override
  void dispose() {
    _service?.close();
    _predictionService?.close();
  }
}
