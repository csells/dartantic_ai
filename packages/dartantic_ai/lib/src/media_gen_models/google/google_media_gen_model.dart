import 'dart:typed_data';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:google_cloud_ai_generativelanguage_v1beta/generativelanguage.dart'
    as gl;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';

import '../../chat_models/google_chat/google_chat_model.dart';
import '../../chat_models/google_chat/google_message_mappers.dart';
import '../../providers/google_api_utils.dart';
import 'google_media_gen_model_options.dart';

/// Media generation model for Google Gemini.
///
/// Supports native image generation via Imagen and code execution fallback
/// for non-image file types (PDF, CSV, etc.) via Python sandbox.
class GoogleMediaGenerationModel
    extends MediaGenerationModel<GoogleMediaGenerationModelOptions> {
  /// Creates a new Google media model instance.
  GoogleMediaGenerationModel({
    required super.name,
    required gl.GenerativeService service,
    required GoogleChatModel chatModel,
    GoogleMediaGenerationModelOptions? defaultOptions,
  }) : _service = service,
       _chatModel = chatModel,
       super(
         defaultOptions:
             defaultOptions ?? const GoogleMediaGenerationModelOptions(),
       );

  static final Logger _logger = Logger('dartantic.media.google');

  final gl.GenerativeService _service;
  final GoogleChatModel _chatModel;

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

    final resolvedOptions = options ?? defaultOptions;

    // Check if any non-image types are requested
    final wantsImages = mimeTypes.any(
      (m) => m == 'image/*' || m.startsWith('image/'),
    );
    final wantsNonImages = mimeTypes.any(
      (m) => m != 'image/*' && !m.startsWith('image/'),
    );

    // Route to appropriate generation path
    if (wantsNonImages && !wantsImages) {
      // Pure non-image request → use code execution
      yield* _generateViaCodeExecution(
        prompt,
        mimeTypes: mimeTypes,
        history: history,
        attachments: attachments,
        options: resolvedOptions,
      );
      return;
    }

    if (wantsImages && wantsNonImages) {
      // Mixed request - generate images first, then non-images
      _logger.info(
        'Mixed MIME types requested - generating images via Imagen, '
        'non-images via code execution',
      );

      // First generate images
      final imageMimes = mimeTypes.where(
        (m) => m == 'image/*' || m.startsWith('image/'),
      ).toList();
      yield* _generateViaImagen(
        prompt,
        mimeTypes: imageMimes,
        history: history,
        options: resolvedOptions,
      );

      // Then generate non-images
      final nonImageMimes = mimeTypes.where(
        (m) => m != 'image/*' && !m.startsWith('image/'),
      ).toList();
      yield* _generateViaCodeExecution(
        prompt,
        mimeTypes: nonImageMimes,
        history: history,
        attachments: attachments,
        options: resolvedOptions,
      );
      return;
    }

    // Pure image request → use native Imagen
    if (attachments.isNotEmpty) {
      throw UnsupportedError(
        'Google native image generation does not support attachments. '
        'Request non-image types to use code execution with attachments.',
      );
    }

    yield* _generateViaImagen(
      prompt,
      mimeTypes: mimeTypes,
      history: history,
      options: resolvedOptions,
    );
  }

  /// Generates media via native Imagen image generation.
  Stream<MediaGenerationResult> _generateViaImagen(
    String prompt, {
    required List<String> mimeTypes,
    required List<ChatMessage> history,
    required GoogleMediaGenerationModelOptions options,
  }) async* {
    final resolvedMimeType = resolveGoogleMediaMimeType(
      mimeTypes,
      options.responseMimeType ?? defaultOptions.responseMimeType,
    );

    final request = _buildRequest(
      prompt: prompt,
      history: history,
      mimeType: resolvedMimeType,
      options: options,
      autoIncludeImageModality: true,
    );

    var chunkIndex = 0;
    await for (final response in _service.streamGenerateContent(request)) {
      chunkIndex++;
      _logger.fine(
        'Received Google Imagen chunk $chunkIndex for model: ${request.model}',
      );
      yield _mapResponse(
        response,
        generationMode: 'imagen',
        chunkIndex: chunkIndex,
        resolvedMimeType: resolvedMimeType,
        requestedMimeTypes: mimeTypes,
      );
    }
  }

  /// Generates media via code execution (Python sandbox).
  Stream<MediaGenerationResult> _generateViaCodeExecution(
    String prompt, {
    required List<String> mimeTypes,
    required List<ChatMessage> history,
    required List<Part> attachments,
    required GoogleMediaGenerationModelOptions options,
  }) async* {
    _logger.info(
      'Using code execution for non-image generation: ${mimeTypes.join(', ')}',
    );

    final augmentedPrompt = _augmentPromptForCodeExecution(prompt, mimeTypes);
    final messages = <ChatMessage>[
      ...history,
      ChatMessage.user(augmentedPrompt, parts: attachments),
    ];

    var chunkIndex = 0;
    await for (final chunk in _chatModel.sendStream(messages)) {
      chunkIndex++;
      _logger.fine('Received Google code execution chunk $chunkIndex');

      final assets = <Part>[];
      final links = <LinkPart>[];

      // Extract DataParts from messages
      for (final message in chunk.messages) {
        for (final part in message.parts) {
          if (part is DataPart) {
            assets.add(part);
          } else if (part is LinkPart) {
            links.add(part);
          }
        }
      }

      final isComplete = chunk.finishReason != FinishReason.unspecified;
      final metadata = <String, dynamic>{
        ...chunk.metadata,
        'generation_mode': 'code_execution',
        'requested_mime_types': mimeTypes,
        'chunk_index': chunkIndex,
      };

      yield MediaGenerationResult(
        id: chunk.id,
        assets: assets,
        links: links,
        messages: chunk.messages,
        metadata: metadata,
        usage: chunk.usage,
        finishReason: chunk.finishReason,
        isComplete: isComplete,
      );
    }
  }

  String _augmentPromptForCodeExecution(String prompt, List<String> mimeTypes) {
    final mimeList = mimeTypes.join(', ');
    return '''
$prompt

Use Python code execution to create the requested files. The output should be
in one of these formats: $mimeList. For PDFs, use libraries like reportlab or
fpdf. For CSV files, use the csv module. Save the file and return it as output.
''';
  }

  /// Resolves response modalities, auto-including IMAGE when needed.
  List<String>? _resolveModalities(
    List<String>? explicit, {
    required bool autoIncludeImageModality,
  }) {
    if (!autoIncludeImageModality) return explicit;

    // Auto-include IMAGE modality for image generation
    if (explicit == null || explicit.isEmpty) {
      return const ['IMAGE'];
    }

    // Check if IMAGE is already included
    final hasImage = explicit.any((m) => m.toUpperCase() == 'IMAGE');
    if (hasImage) return explicit;

    // Add IMAGE to the existing modalities
    return [...explicit, 'IMAGE'];
  }

  gl.GenerateContentRequest _buildRequest({
    required String prompt,
    required List<ChatMessage> history,
    required String mimeType,
    required GoogleMediaGenerationModelOptions options,
    bool autoIncludeImageModality = false,
  }) {
    final contents = <gl.Content>[
      ...history.toContentList(),
      gl.Content(
        role: 'user',
        parts: [gl.Part(text: prompt)],
      ),
    ];

    final imageConfig = gl.ImageConfig(aspectRatio: options.aspectRatio);

    // Google's responseMimeType only accepts text-based formats
    // (text/plain, application/json, etc.), not image MIME types.
    // For image generation, output format is controlled by responseModalities.
    final textResponseMimeType = mimeType.startsWith('image/')
        ? ''
        : mimeType;

    // Auto-include IMAGE modality when generating images
    final modalities = _resolveModalities(
      options.responseModalities,
      autoIncludeImageModality: autoIncludeImageModality,
    );

    final generationConfig = gl.GenerationConfig(
      temperature: options.temperature,
      topP: options.topP,
      topK: options.topK,
      maxOutputTokens: options.maxOutputTokens,
      responseMimeType: textResponseMimeType,
      candidateCount: options.imageSampleCount,
      imageConfig: imageConfig,
      responseModalities: mapGoogleModalities(modalities),
    );

    return gl.GenerateContentRequest(
      model: normalizeGoogleModelName(name),
      contents: contents,
      generationConfig: generationConfig,
      safetySettings:
          options.safetySettings?.toSafetySettings() ??
          const <gl.SafetySetting>[],
    );
  }

  /// Test-only hook to expose response mapping without hitting the network.
  @visibleForTesting
  MediaGenerationResult mapResponseForTest(
    gl.GenerateContentResponse response,
  ) =>
      _mapResponse(
        response,
        generationMode: 'test',
        chunkIndex: 0,
        resolvedMimeType: 'test/unknown',
        requestedMimeTypes: const [],
      );

  MediaGenerationResult _mapResponse(
    gl.GenerateContentResponse response, {
    required String generationMode,
    required int chunkIndex,
    required String resolvedMimeType,
    required List<String> requestedMimeTypes,
  }) {
    final assets = <DataPart>[];
    final links = <LinkPart>[];
    final messages = <ChatMessage>[];
    final finishReason = _resolveFinishReason(response);
    final isComplete = finishReason != FinishReason.unspecified;

    for (final candidate in response.candidates) {
      if (candidate.content != null) {
        for (final part in candidate.content!.parts) {
          if (part.inlineData != null && part.inlineData!.data != null) {
            final data = part.inlineData!;
            _logger.info('Received inlineData: ${data.mimeType}');
            assets.add(
              DataPart(
                Uint8List.fromList(data.data!),
                mimeType: data.mimeType,
                name: _suggestName(data.mimeType, assets.length),
              ),
            );
          } else if (part.fileData != null &&
              part.fileData!.fileUri.isNotEmpty) {
            _logger.info('Received fileData: ${part.fileData!.fileUri}');
            final uri = Uri.parse(part.fileData!.fileUri);
            final name = uri.pathSegments.isNotEmpty
                ? uri.pathSegments.last
                : null;
            links.add(
              LinkPart(
                uri,
                mimeType: part.fileData!.mimeType,
                name: name?.isEmpty ?? true ? null : name,
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

    final metadata = _mergeMetadata(
      _extractMetadata(response),
      {
        'generation_mode': generationMode,
        'chunk_index': chunkIndex,
        'resolved_mime_type': resolvedMimeType,
        'requested_mime_types': requestedMimeTypes,
      },
    );

    return MediaGenerationResult(
      assets: assets,
      links: links,
      messages: messages,
      metadata: metadata,
      usage: response.usageMetadata == null
          ? null
          : LanguageModelUsage(
              promptTokens: response.usageMetadata!.promptTokenCount,
              responseTokens: response.usageMetadata!.candidatesTokenCount,
              totalTokens: response.usageMetadata!.totalTokenCount,
            ),
      finishReason: finishReason,
      isComplete: isComplete,
    );
  }

  Map<String, dynamic> _mergeMetadata(
    Map<String, dynamic>? base,
    Map<String, dynamic> overlay,
  ) {
    final merged = <String, dynamic>{
      if (base != null) ...base,
      ...overlay,
    };

    merged.removeWhere((_, value) {
      if (value == null) return true;
      if (value is String && value.isEmpty) return true;
      if (value is Iterable && value.isEmpty) return true;
      return false;
    });

    return merged;
  }

  Map<String, dynamic> _extractMetadata(gl.GenerateContentResponse response) {
    final metadata = <String, dynamic>{'model': name};

    final blockReason = response.promptFeedback?.blockReason.value;
    if (blockReason != null) {
      metadata['block_reason'] = blockReason;
    }

    final modelVersion = response.modelVersion;
    if (modelVersion.isNotEmpty) {
      metadata['model_version'] = modelVersion;
    }

    final safetyRatings = response.candidates
        .expand((c) => c.safetyRatings)
        .map(
          (rating) => {
            'category': rating.category.value,
            'probability': rating.probability.value,
          },
        )
        .toList(growable: false);
    if (safetyRatings.isNotEmpty) {
      metadata['safety_ratings'] = safetyRatings;
    }

    final citations = response.candidates
        .map(
          (c) =>
              c.citationMetadata?.citationSources ??
              const <gl.CitationSource>[],
        )
        .expand((s) => s)
        .map(
          (source) => {
            'start_index': source.startIndex,
            'end_index': source.endIndex,
            'uri': source.uri,
            'license': source.license,
          },
        )
        .toList(growable: false);
    if (citations.isNotEmpty) {
      metadata['citation_metadata'] = citations;
    }

    metadata.removeWhere((_, value) {
      if (value == null) return true;
      if (value is String && value.isEmpty) return true;
      if (value is Iterable && value.isEmpty) return true;
      return false;
    });

    return metadata;
  }

  FinishReason _resolveFinishReason(gl.GenerateContentResponse response) {
    for (final candidate in response.candidates) {
      final mapped = mapGoogleMediaFinishReason(candidate.finishReason);
      if (mapped != FinishReason.unspecified) return mapped;
    }
    return FinishReason.unspecified;
  }

  String _suggestName(String mimeType, int index) {
    final extension = Part.extensionFromMimeType(mimeType);
    final suffix = extension == null ? '' : '.$extension';
    return 'image_$index$suffix';
  }

  @override
  void dispose() {
    _service.close();
    _chatModel.dispose();
  }
}

/// Maps Google finish reasons to Dartantic finish reasons.
@visibleForTesting
  FinishReason mapGoogleMediaFinishReason(gl.Candidate_FinishReason? reason) =>
      switch (reason) {
        gl.Candidate_FinishReason.stop => FinishReason.stop,
        gl.Candidate_FinishReason.maxTokens => FinishReason.length,
        gl.Candidate_FinishReason.safety ||
      gl.Candidate_FinishReason.blocklist ||
      gl.Candidate_FinishReason.prohibitedContent ||
      gl.Candidate_FinishReason.imageSafety ||
      gl.Candidate_FinishReason.spii => FinishReason.contentFilter,
        gl.Candidate_FinishReason.recitation => FinishReason.recitation,
        _ => FinishReason.unspecified,
      };

/// Validates and maps response modalities to Google enums.
@visibleForTesting
List<gl.GenerationConfig_Modality> mapGoogleModalities(
  List<String>? modalities,
) {
  const allowed = {'TEXT', 'IMAGE', 'AUDIO'};
  if (modalities == null) return const [];

  final normalized = modalities.map((m) => m.toUpperCase()).toList();
  final invalid = normalized.where((m) => !allowed.contains(m)).toList();
  if (invalid.isNotEmpty) {
    throw UnsupportedError(
      'Unsupported response modalities: ${invalid.join(', ')}. '
      'Allowed: ${allowed.join(', ')}.',
    );
  }

  return normalized
      .map(
        (m) => switch (m) {
          'TEXT' => gl.GenerationConfig_Modality.text,
          'IMAGE' => gl.GenerationConfig_Modality.image,
          'AUDIO' => gl.GenerationConfig_Modality.audio,
          _ => gl.GenerationConfig_Modality.modalityUnspecified,
        },
      )
      .toList(growable: false);
}

/// Resolves the best MIME type for Google media generation.
@visibleForTesting
String resolveGoogleMediaMimeType(
  List<String> requested,
  String? overrideMime,
) {
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
