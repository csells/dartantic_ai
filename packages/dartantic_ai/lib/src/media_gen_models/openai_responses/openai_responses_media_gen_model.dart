import 'dart:convert';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:mime/mime.dart';

import '../../chat_models/openai_responses/openai_responses_chat_model.dart';
import '../../chat_models/openai_responses/openai_responses_chat_options.dart';
import '../../chat_models/openai_responses/openai_responses_options_mapper.dart';
import '../../chat_models/openai_responses/openai_responses_server_side_tools.dart';
import '../../chat_models/openai_responses/openai_responses_tool_types.dart';
import 'openai_responses_media_gen_model_options.dart';

/// Media generation model built on top of the OpenAI Responses API.
class OpenAIResponsesMediaGenerationModel
    extends MediaGenerationModel<OpenAIResponsesMediaGenerationModelOptions> {
  /// Creates a new OpenAI Responses media model instance.
  OpenAIResponsesMediaGenerationModel({
    required super.name,
    required super.defaultOptions,
    required OpenAIResponsesChatModel chatModel,
    super.tools,
  }) : _chatModel = chatModel;

  static final Logger _logger = Logger(
    'dartantic.media.models.openai_responses',
  );

  static const int _defaultPartialImages = 0;

  final OpenAIResponsesChatModel _chatModel;

  @override
  Stream<MediaGenerationResult> generateMediaStream(
    String prompt, {
    required List<String> mimeTypes,
    List<ChatMessage> history = const [],
    List<Part> attachments = const [],
    OpenAIResponsesMediaGenerationModelOptions? options,
    JsonSchema? outputSchema,
  }) async* {
    if (outputSchema != null) {
      throw UnsupportedError(
        'OpenAI Responses media generation does not support output schemas.',
      );
    }
    final wantsImages = mimeTypes.any(_isImageMimeType);
    final wantsOtherFiles = mimeTypes.any((m) => !_isImageMimeType(m));
    final generationMode = wantsImages && wantsOtherFiles
        ? 'mixed'
        : wantsImages
        ? 'image_generation'
        : 'code_interpreter';

    final serverSideTools = <OpenAIServerSideTool>{
      if (wantsImages) OpenAIServerSideTool.imageGeneration,
      if (wantsOtherFiles || !wantsImages) OpenAIServerSideTool.codeInterpreter,
    };

    _logger.info(
      'Starting OpenAI media generation with ${history.length} history '
      'messages and MIME types: ${mimeTypes.join(', ')}',
    );

    final resolved = _resolve(defaultOptions, options);
    final chatOptions = _toChatOptions(
      resolved,
      serverSideTools: serverSideTools,
      includeImageConfig: wantsImages,
    );

    final messages = <ChatMessage>[
      // Add system instruction for code interpreter to improve file citation
      // reliability. The model sometimes omits container_file_citation
      // annotations; this instruction encourages proper file referencing.
      if (wantsOtherFiles)
        ChatMessage.system(
          'When you create files using code interpreter, always provide a '
          'clear download link referencing the exact file path. Format file '
          'references as clickable links.',
        ),
      ...history,
      ChatMessage.user(prompt, parts: attachments),
    ];

    final tracker = _OpenAIResponsesMediaTracker();

    // Accumulate all messages across chunks - DataParts only appear in the
    // accumulated collection, not in individual chunk.messages
    final accumulatedMessages = <ChatMessage>[];

    var chunkIndex = 0;
    await for (final chunk in _chatModel.sendStream(
      messages,
      options: chatOptions,
    )) {
      accumulatedMessages.addAll(chunk.messages);
      chunkIndex++;
      yield _mapChunk(
        chunk,
        tracker,
        accumulatedMessages,
        generationMode: generationMode,
        requestedMimeTypes: mimeTypes,
        chunkIndex: chunkIndex,
      );
    }
  }

  @override
  void dispose() => _chatModel.dispose();

  @visibleForTesting
  /// Test-only hook to map a chunk without invoking the network.
  MediaGenerationResult mapChunkForTest(
    ChatResult<ChatMessage> result, {
    required String generationMode,
    required List<String> requestedMimeTypes,
    int chunkIndex = 0,
    List<ChatMessage> accumulatedMessages = const [],
  }) => _mapChunk(
    result,
    _OpenAIResponsesMediaTracker(),
    List<ChatMessage>.from(accumulatedMessages),
    generationMode: generationMode,
    requestedMimeTypes: requestedMimeTypes,
    chunkIndex: chunkIndex,
  );

  MediaGenerationResult _mapChunk(
    ChatResult<ChatMessage> result,
    _OpenAIResponsesMediaTracker tracker,
    List<ChatMessage> accumulatedMessages, {
    required String generationMode,
    required List<String> requestedMimeTypes,
    required int chunkIndex,
  }) {
    final assets = <Part>[];
    final links = <LinkPart>[];
    final metadata = Map<String, dynamic>.from(result.metadata);

    metadata.addAll({
      'generation_mode': generationMode,
      'requested_mime_types': requestedMimeTypes,
      'chunk_index': chunkIndex,
    });

    final (metadataAssets, metadataLinks) = _extractAssetsFromMetadata(
      metadata,
      tracker,
    );
    assets.addAll(metadataAssets);
    links.addAll(metadataLinks);

    // Search accumulated messages for DataParts - they only appear in the
    // accumulated collection, not in individual chunk.messages
    for (final message in accumulatedMessages) {
      for (final part in message.parts) {
        if (part is DataPart) {
          assets.add(part);
        } else if (part is LinkPart) {
          links.add(part);
        }
      }
    }

    final isComplete = result.finishReason != FinishReason.unspecified;

    if (isComplete) {
      _logger.fine(
        'Media generation completed with ${assets.length} assets '
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

  static _ResolvedMediaSettings _resolve(
    OpenAIResponsesMediaGenerationModelOptions base,
    OpenAIResponsesMediaGenerationModelOptions? override,
  ) {
    final partialImages =
        override?.partialImages ?? base.partialImages ?? _defaultPartialImages;
    final quality =
        override?.quality ?? base.quality ?? ImageGenerationQuality.auto;
    final size = override?.size ?? base.size ?? ImageGenerationSize.auto;
    final store = override?.store ?? base.store;
    final metadata = OpenAIResponsesOptionsMapper.mergeMetadata(
      base.metadata,
      override?.metadata,
    );
    final include = override?.include ?? base.include;
    final user = override?.user ?? base.user;

    return _ResolvedMediaSettings(
      partialImages: partialImages,
      quality: quality,
      size: size,
      store: store,
      metadata: metadata,
      include: include == null ? null : List<String>.from(include),
      user: user,
    );
  }

  static OpenAIResponsesChatModelOptions _toChatOptions(
    _ResolvedMediaSettings settings, {
    required Set<OpenAIServerSideTool> serverSideTools,
    required bool includeImageConfig,
  }) => OpenAIResponsesChatModelOptions(
    store: settings.store,
    metadata: settings.metadata == null
        ? null
        : Map<String, dynamic>.from(settings.metadata!),
    include: settings.include,
    user: settings.user,
    serverSideTools: serverSideTools.isEmpty ? null : serverSideTools,
    imageGenerationConfig: includeImageConfig
        ? ImageGenerationConfig(
            partialImages: settings.partialImages,
            quality: settings.quality,
            size: settings.size,
          )
        : null,
  );

  bool _isImageMimeType(String value) =>
      value == 'image/*' ||
      value.startsWith('image/') ||
      value == 'image/png' ||
      value == 'image/jpeg' ||
      value == 'image/webp';

  (List<Part> assets, List<LinkPart> links) _extractAssetsFromMetadata(
    Map<String, dynamic> metadata,
    _OpenAIResponsesMediaTracker tracker,
  ) {
    final assets = <Part>[];
    final links = <LinkPart>[];

    final imageEvents = metadata[OpenAIResponsesToolTypes.imageGeneration];
    if (imageEvents is List) {
      for (final event in imageEvents) {
        if (event is! Map) continue;
        final base64 = event['partial_image_b64'];
        final index = event['partial_image_index'];
        if (base64 is! String || base64.isEmpty) continue;
        if (index is! int) continue;

        final emission = tracker.registerPartialPreview(index, base64);
        if (emission == null) continue;

        final bytes = base64Decode(base64);
        final inferredMime =
            lookupMimeType('image.bin', headerBytes: bytes) ?? 'image/png';
        final extension = Part.extensionFromMimeType(inferredMime);
        final name = tracker.buildPartialName(index, emission, extension);
        assets.add(DataPart(bytes, mimeType: inferredMime, name: name));
      }
    }

    return (assets, links);
  }
}

class _ResolvedMediaSettings {
  const _ResolvedMediaSettings({
    required this.partialImages,
    required this.quality,
    required this.size,
    this.store,
    this.metadata,
    this.include,
    this.user,
  });

  final int partialImages;
  final ImageGenerationQuality quality;
  final ImageGenerationSize size;
  final bool? store;
  final Map<String, dynamic>? metadata;
  final List<String>? include;
  final String? user;
}

class _OpenAIResponsesMediaTracker {
  final Set<String> _seenPartialKeys = <String>{};
  final Map<int, int> _partialEmissions = <int, int>{};

  int? registerPartialPreview(int index, String payload) {
    final key = '$index::$payload';
    if (!_seenPartialKeys.add(key)) return null;
    final emission = _partialEmissions[index] ?? 0;
    _partialEmissions[index] = emission + 1;
    return emission;
  }

  String buildPartialName(int index, int emission, String? extension) {
    final suffix = extension == null || extension.isEmpty ? '' : '.$extension';
    if (emission == 0) return 'partial_$index$suffix';
    return 'partial_${index}_$emission$suffix';
  }
}
