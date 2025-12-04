import 'dart:typed_data';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:google_cloud_ai_generativelanguage_v1beta/generativelanguage.dart'
    as gl;
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../../chat_models/google_chat/google_chat_model.dart';
import '../../chat_models/google_chat/google_chat_options.dart';
import '../../chat_models/google_chat/google_server_side_tools.dart';
import '../../custom_http_client.dart';
import '../../providers/google_api_utils.dart';
import '../../retry_http_client.dart';
import 'google_media_gen_model_options.dart';

/// Media generation model for Google Gemini.
class GoogleMediaGenerationModel
    extends MediaGenerationModel<GoogleMediaGenerationModelOptions> {
  /// Creates a new Google media model instance.
  GoogleMediaGenerationModel({
    required super.name,
    required String apiKey,
    required Uri baseUrl,
    GoogleMediaGenerationModelOptions? defaultOptions,
    http.Client? client,
  }) : super(
         defaultOptions:
             defaultOptions ?? const GoogleMediaGenerationModelOptions(),
       ) {
    final httpClient = client ?? RetryHttpClient(inner: http.Client());
    _httpClient = CustomHttpClient(
      baseHttpClient: httpClient,
      baseUrl: baseUrl,
      headers: {'x-goog-api-key': apiKey},
      queryParams: const {},
    );
    _service = gl.GenerativeService(client: _httpClient);
  }

  static final Logger _logger = Logger('dartantic.media.google');

  late final gl.GenerativeService _service;
  late final CustomHttpClient _httpClient;

  @override
  Stream<MediaGenerationResult> generateMediaStream(
    String prompt, {
    required List<String> mimeTypes,
    List<ChatMessage> history = const [],
    List<Part> attachments = const [],
    GoogleMediaGenerationModelOptions? options,
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

    // Check if any requested MIME type is NOT an image
    final hasNonImageMimeType = mimeTypes.any((m) => !m.startsWith('image/'));

    if (hasNonImageMimeType) {
      yield* _generateWithCodeExecution(
        prompt,
        mimeTypes: mimeTypes,
        history: history,
        options: resolvedOptions,
      );
      return;
    }

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
    // Use streamGenerateContent but expect image data in response
    await for (final response in _service.streamGenerateContent(request)) {
      chunkIndex++;
      _logger.fine(
        'Received Google media chunk $chunkIndex for model: ${request.model}',
      );
      yield _mapResponse(response, resolvedMimeType);
    }
  }

  Stream<MediaGenerationResult> _generateWithCodeExecution(
    String prompt, {
    required List<String> mimeTypes,
    required List<ChatMessage> history,
    required GoogleMediaGenerationModelOptions options,
  }) async* {
    _logger.info(
      'Delegating media generation to ChatModel with code execution for '
      'MIME types: $mimeTypes',
    );

    // Create a chat model with code execution enabled
    // We must use a model that supports code execution (e.g. gemini-2.5-flash),
    // as the image model (gemini-2.5-flash-image) likely does not.
    final chatModel = GoogleChatModel(
      name: 'gemini-2.5-flash',
      apiKey: _httpClient.headers['x-goog-api-key']!,
      baseUrl: _httpClient.baseUrl,
      client: _httpClient.baseHttpClient,
      defaultOptions: GoogleChatModelOptions(
        serverSideTools: const {GoogleServerSideTool.codeExecution},
        safetySettings: options.safetySettings,
      ),
    );

    try {
      final systemPrompt = '''
You are a helpful assistant that generates files using code execution.
The user wants a file of type: ${mimeTypes.join(', ')}.

IMPORTANT INSTRUCTIONS:
1. Write and execute Python code to generate the requested file.
2. After creating the file, you MUST read it back and return it as binary data.
3. For binary files (PDF, images, etc.), use: print(open('filename', 'rb').read())
4. For text files (CSV, TXT, etc.), use: print(open('filename', 'r').read())
5. The file content MUST appear in your response so it can be captured.
6. Do not just describe how to create the file - actually create it AND output its contents.
''';

      final messages = [
        ChatMessage.system(systemPrompt),
        ...history,
        ChatMessage.user(prompt),
      ];

      await for (final result in chatModel.sendStream(messages)) {
        // Map ChatResult to MediaGenerationResult
        // Extract DataParts (inlineData) or LinkParts (fileData) from all
        // messages, not just the direct output (code execution may return
        // files in message history)
        final assets = <DataPart>[];
        final links = <LinkPart>[];

        for (final message in result.messages) {
          for (final part in message.parts) {
            if (part is DataPart) {
              assets.add(part);
            } else if (part is LinkPart) {
              links.add(part);
            }
          }
        }

        yield MediaGenerationResult(
          assets: assets,
          links: links,
          messages: result.messages,
          metadata: result.metadata,
          usage: result.usage,
          finishReason: result.finishReason,
          isComplete: result.finishReason != FinishReason.unspecified,
        );
      }
    } finally {
      chatModel.dispose();
    }
  }

  gl.GenerateContentRequest _buildRequest({
    required String prompt,
    required List<ChatMessage> history,
    required String mimeType,
    required GoogleMediaGenerationModelOptions options,
  }) {
    final contents = _convertMessagesToContents(history)
      ..add(
        gl.Content(
          role: 'user',
          parts: [gl.Part(text: prompt)],
        ),
      );

    final imageConfig = gl.ImageConfig(aspectRatio: options.aspectRatio);

    final generationConfig = gl.GenerationConfig(
      temperature: options.temperature,
      topP: options.topP,
      topK: options.topK,
      maxOutputTokens: options.maxOutputTokens,
      responseMimeType: options.responseMimeType ?? '',
      candidateCount: options.imageSampleCount,
      imageConfig: imageConfig,
      responseModalities:
          options.responseModalities
              ?.map(
                (m) => switch (m.toUpperCase()) {
                  'TEXT' => gl.GenerationConfig_Modality.text,
                  'IMAGE' => gl.GenerationConfig_Modality.image,
                  'AUDIO' => gl.GenerationConfig_Modality.audio,
                  _ => gl.GenerationConfig_Modality.modalityUnspecified,
                },
              )
              .toList() ??
          const [],
    );

    return gl.GenerateContentRequest(
      model: normalizeGoogleModelName(name),
      contents: contents,
      generationConfig: generationConfig,
      safetySettings: _mapSafetySettings(options.safetySettings) ?? const [],
    );
  }

  MediaGenerationResult _mapResponse(
    gl.GenerateContentResponse response,
    String mimeType,
  ) {
    final assets = <DataPart>[];
    final messages = <ChatMessage>[];

    for (final candidate in response.candidates) {
      if (candidate.content != null) {
        for (final part in candidate.content!.parts) {
          if (part.inlineData != null) {
            _logger.info('Received inlineData: ${part.inlineData!.mimeType}');
            assets.add(
              DataPart(
                Uint8List.fromList(part.inlineData!.data!),
                mimeType: part.inlineData!.mimeType,
                name: _suggestName(part.inlineData!.mimeType, assets.length),
              ),
            );
          } else if (part.text != null) {
            _logger.info('Received text: ${part.text}');
            messages.add(
              ChatMessage(
                role: ChatMessageRole.model,
                parts: [TextPart(part.text!)],
              ),
            );
          } else if (part.fileData != null) {
            _logger.info('Received fileData: ${part.fileData!.fileUri}');
          } else if (part.functionCall != null) {
            _logger.info('Received functionCall: ${part.functionCall!.name}');
          } else if (part.executableCode != null) {
            _logger.info('Received executableCode');
          } else if (part.codeExecutionResult != null) {
            _logger.info('Received codeExecutionResult');
          } else {
            _logger.info('Received unknown part type');
          }
        }
      }
    }

    return MediaGenerationResult(
      assets: assets,
      messages: messages,
      metadata:
          const <String, dynamic>{}, // Metadata not easily accessible in stream
      usage: response.usageMetadata == null
          ? null
          : LanguageModelUsage(
              promptTokens: response.usageMetadata!.promptTokenCount,
              responseTokens: response.usageMetadata!.candidatesTokenCount,
              totalTokens: response.usageMetadata!.totalTokenCount,
            ),
      finishReason: FinishReason.unspecified, // Map if needed
      isComplete: true, // Stream chunks are usually complete parts?
    );
  }

  List<gl.Content> _convertMessagesToContents(List<ChatMessage> messages) {
    final contents = <gl.Content>[];
    for (final message in messages) {
      final textParts = message.parts.whereType<TextPart>().toList();
      if (textParts.isEmpty) continue;

      final role = switch (message.role) {
        ChatMessageRole.model => 'model',
        _ => 'user',
      };

      contents.add(
        gl.Content(
          role: role,
          parts: textParts.map((p) => gl.Part(text: p.text)).toList(),
        ),
      );
    }
    return contents;
  }

  List<gl.SafetySetting>? _mapSafetySettings(
    List<ChatGoogleGenerativeAISafetySetting>? safetySettings,
  ) {
    if (safetySettings == null || safetySettings.isEmpty) return null;
    return safetySettings.map((setting) {
      final category = switch (setting.category) {
        ChatGoogleGenerativeAISafetySettingCategory.unspecified =>
          gl.HarmCategory.harmCategoryUnspecified,
        ChatGoogleGenerativeAISafetySettingCategory.harassment =>
          gl.HarmCategory.harmCategoryHarassment,
        ChatGoogleGenerativeAISafetySettingCategory.hateSpeech =>
          gl.HarmCategory.harmCategoryHateSpeech,
        ChatGoogleGenerativeAISafetySettingCategory.sexuallyExplicit =>
          gl.HarmCategory.harmCategorySexuallyExplicit,
        ChatGoogleGenerativeAISafetySettingCategory.dangerousContent =>
          gl.HarmCategory.harmCategoryDangerousContent,
      };

      final threshold = switch (setting.threshold) {
        ChatGoogleGenerativeAISafetySettingThreshold.unspecified =>
          gl.SafetySetting_HarmBlockThreshold.harmBlockThresholdUnspecified,
        ChatGoogleGenerativeAISafetySettingThreshold.blockLowAndAbove =>
          gl.SafetySetting_HarmBlockThreshold.blockLowAndAbove,
        ChatGoogleGenerativeAISafetySettingThreshold.blockMediumAndAbove =>
          gl.SafetySetting_HarmBlockThreshold.blockMediumAndAbove,
        ChatGoogleGenerativeAISafetySettingThreshold.blockOnlyHigh =>
          gl.SafetySetting_HarmBlockThreshold.blockOnlyHigh,
        ChatGoogleGenerativeAISafetySettingThreshold.blockNone =>
          gl.SafetySetting_HarmBlockThreshold.blockNone,
      };

      return gl.SafetySetting(category: category, threshold: threshold);
    }).toList();
  }

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
    _service.close();
  }
}
