import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../../chat_models/google_chat/google_chat_options.dart';
import '../../retry_http_client.dart';
import 'google_media_generation_client.dart';
import 'google_media_model_options.dart';

/// Media generation model for Google Gemini.
class GoogleMediaModel extends MediaGenerationModel<GoogleMediaModelOptions> {
  /// Creates a new Google media model instance.
  GoogleMediaModel({
    required super.name,
    required String apiKey,
    required Uri baseUrl,
    GoogleMediaModelOptions? defaultOptions,
    http.Client? client,
  }) : super(
         defaultOptions: defaultOptions ?? const GoogleMediaModelOptions(),
       ) {
    final resolvedClient = client ?? RetryHttpClient(inner: http.Client());
    _httpClient = resolvedClient;
    _generationClient = GoogleMediaGenerationClient(
      apiKey: apiKey,
      baseUrl: baseUrl,
      httpClient: resolvedClient,
    );
  }

  static final Logger _logger = Logger('dartantic.media.google');

  late final GoogleMediaGenerationClient _generationClient;
  http.Client? _httpClient;

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

    if (attachments.isNotEmpty) {
      throw UnsupportedError(
        'Google media generation does not support attachments.',
      );
    }

    final resolvedOptions = options ?? defaultOptions;
    final resolvedMimeType = _resolveMimeType(
      mimeTypes,
      resolvedOptions.responseMimeType ?? defaultOptions.responseMimeType,
    );

    final request = _buildRequest(
      prompt: prompt,
      history: history,
      mimeType: resolvedMimeType,
      options: resolvedOptions,
    );

    var chunkIndex = 0;
    await for (final chunk in _generationClient.streamGenerateContent(
      request,
    )) {
      chunkIndex++;
      _logger.fine(
        'Received Google media chunk $chunkIndex for model: ${request.model}',
      );
      yield _mapChunk(chunk, resolvedMimeType);
    }
  }

  GoogleMediaGenerationRequest _buildRequest({
    required String prompt,
    required List<ChatMessage> history,
    required String mimeType,
    required GoogleMediaModelOptions options,
  }) {
    final contents = _convertMessagesToContents(history)
      ..add({
        'role': 'user',
        'parts': [
          {'text': prompt},
        ],
      });

    final generationConfig = <String, Object?>{
      'temperature': options.temperature,
      'topP': options.topP,
      'topK': options.topK,
      'maxOutputTokens': options.maxOutputTokens,
      if (!mimeType.startsWith('image/')) 'responseMimeType': mimeType,
      'responseModalities': [_responseModalityForMime(mimeType)],
      'imageConfig': _buildImageConfig(options),
    }..removeWhere((key, value) => value == null);

    return GoogleMediaGenerationRequest(
      model: name,
      contents: contents,
      generationConfig: generationConfig.isEmpty ? null : generationConfig,
      safetySettings: _mapSafetySettings(
        options.safetySettings ?? defaultOptions.safetySettings,
      ),
    );
  }

  MediaGenerationResult _mapChunk(GoogleMediaChunk chunk, String mimeType) {
    final assets = chunk.assets
        .map(
          (asset) => DataPart(
            base64Decode(asset.data),
            mimeType: asset.mimeType,
            name:
                asset.name ??
                _suggestName(asset.mimeType, chunk.assets.indexOf(asset)),
          ),
        )
        .toList(growable: false);

    final messages = chunk.messages
        .map(
          (message) => ChatMessage(
            role: message.role == 'user'
                ? ChatMessageRole.user
                : ChatMessageRole.model,
            parts: [TextPart(message.text)],
          ),
        )
        .toList(growable: false);

    return MediaGenerationResult(
      id: chunk.id,
      assets: assets,
      messages: messages,
      metadata: Map<String, dynamic>.from(chunk.metadata),
      usage: chunk.usage == null
          ? null
          : LanguageModelUsage(
              promptTokens: chunk.usage!.promptTokens,
              responseTokens: chunk.usage!.candidatesTokens,
              totalTokens: chunk.usage!.totalTokens,
            ),
      finishReason: _mapFinishReason(chunk.finishReason),
      isComplete: chunk.isComplete,
    );
  }

  List<Map<String, Object?>> _convertMessagesToContents(
    List<ChatMessage> messages,
  ) {
    final contents = <Map<String, Object?>>[];
    for (final message in messages) {
      final textParts = message.parts.whereType<TextPart>().toList();
      if (textParts.isEmpty) continue;

      final role = switch (message.role) {
        ChatMessageRole.model => 'model',
        _ => 'user',
      };

      contents.add({
        'role': role,
        'parts': textParts.map((part) => {'text': part.text}).toList(),
      });
    }
    return contents;
  }

  Map<String, Object?>? _buildImageConfig(GoogleMediaModelOptions options) {
    final config = <String, Object?>{
      if (options.imageSampleCount != null) 'number': options.imageSampleCount,
      if (options.aspectRatio != null && options.aspectRatio!.isNotEmpty)
        'aspectRatio': options.aspectRatio,
      if (options.negativePrompt != null && options.negativePrompt!.isNotEmpty)
        'negativePrompt': options.negativePrompt,
      if (options.addWatermark != null)
        'includeWatermark': options.addWatermark,
    };
    return config.isEmpty ? null : config;
  }

  List<Map<String, Object?>>? _mapSafetySettings(
    List<ChatGoogleGenerativeAISafetySetting>? safetySettings,
  ) {
    if (safetySettings == null || safetySettings.isEmpty) return null;
    return safetySettings
        .map(
          (setting) => {
            'category': setting.category.apiName,
            'threshold': setting.threshold.apiName,
          },
        )
        .toList(growable: false);
  }

  String _responseModalityForMime(String mimeType) =>
      mimeType.startsWith('image/') ? 'IMAGE' : 'TEXT';

  FinishReason _mapFinishReason(String? finishReason) => switch (finishReason) {
    'FINISH_REASON_STOP' => FinishReason.stop,
    'FINISH_REASON_MAX_TOKENS' => FinishReason.length,
    'FINISH_REASON_SAFETY' => FinishReason.contentFilter,
    'FINISH_REASON_RECITATION' => FinishReason.recitation,
    'FINISH_REASON_BLOCKLIST' => FinishReason.contentFilter,
    'FINISH_REASON_PROHIBITED_CONTENT' => FinishReason.contentFilter,
    'FINISH_REASON_SPII' => FinishReason.contentFilter,
    _ => FinishReason.unspecified,
  };

  String _suggestName(String mimeType, int index) {
    final extension = Part.extensionFromMimeType(mimeType);
    final suffix = extension == null ? '' : '.$extension';
    return 'image_$index$suffix';
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

  @override
  void dispose() {
    _httpClient?.close();
  }
}

extension on ChatGoogleGenerativeAISafetySettingCategory {
  String get apiName => switch (this) {
    ChatGoogleGenerativeAISafetySettingCategory.unspecified =>
      'HARM_CATEGORY_UNSPECIFIED',
    ChatGoogleGenerativeAISafetySettingCategory.harassment =>
      'HARM_CATEGORY_HARASSMENT',
    ChatGoogleGenerativeAISafetySettingCategory.hateSpeech =>
      'HARM_CATEGORY_HATE_SPEECH',
    ChatGoogleGenerativeAISafetySettingCategory.sexuallyExplicit =>
      'HARM_CATEGORY_SEXUALLY_EXPLICIT',
    ChatGoogleGenerativeAISafetySettingCategory.dangerousContent =>
      'HARM_CATEGORY_DANGEROUS_CONTENT',
  };
}

extension on ChatGoogleGenerativeAISafetySettingThreshold {
  String get apiName => switch (this) {
    ChatGoogleGenerativeAISafetySettingThreshold.unspecified =>
      'BLOCK_THRESHOLD_UNSPECIFIED',
    ChatGoogleGenerativeAISafetySettingThreshold.blockLowAndAbove =>
      'BLOCK_LOW_AND_ABOVE',
    ChatGoogleGenerativeAISafetySettingThreshold.blockMediumAndAbove =>
      'BLOCK_MEDIUM_AND_ABOVE',
    ChatGoogleGenerativeAISafetySettingThreshold.blockOnlyHigh =>
      'BLOCK_ONLY_HIGH',
    ChatGoogleGenerativeAISafetySettingThreshold.blockNone => 'BLOCK_NONE',
  };
}
