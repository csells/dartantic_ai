import 'dart:async';

import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:http/http.dart' as http;
import 'package:json_schema/json_schema.dart';
import 'package:logging/logging.dart';

import '../../chat_models/anthropic_chat/anthropic_chat_model.dart';
import '../../chat_models/anthropic_chat/anthropic_chat_options.dart';
import 'anthropic_files_client.dart';
import 'anthropic_media_gen_model_options.dart';
import 'anthropic_tool_deliverable_tracker.dart';

/// Media generation model backed by the Anthropic code execution tool.
class AnthropicMediaGenerationModel
    extends MediaGenerationModel<AnthropicMediaGenerationModelOptions> {
  /// Creates a new Anthropic media model instance.
  AnthropicMediaGenerationModel({
    required super.name,
    required super.defaultOptions,
    required AnthropicChatModel chatModel,
    required String apiKey,
    Uri? baseUrl,
    http.Client? httpClient,
    List<String> betaFeatures = const [],
  }) : _chatModel = chatModel,
       _filesClient = AnthropicFilesClient(
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
  final AnthropicFilesClient _filesClient;

  /// Builds chat model options for provided media defaults.
  static AnthropicChatOptions buildChatOptions(
    AnthropicMediaGenerationModelOptions base,
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
    AnthropicMediaGenerationModelOptions? options,
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

    _logger.info(
      'Starting Anthropic media generation with ${history.length} history '
      'messages and MIME types: ${mimeTypes.join(', ')}',
    );

    final resolved = _resolve(defaultOptions, options);
    final chatOptions = _toChatOptions(resolved);
    final tracker = AnthropicToolDeliverableTracker(
      _filesClient,
      targetMimeTypes: mimeTypes.toSet(),
    );
    final augmentedPrompt = _augmentPrompt(prompt, mimeTypes);

    final messages = <ChatMessage>[
      ChatMessage.system(r"""
You are using Anthropic's server-side code execution tool. Whenever you create
or modify a file, you MUST copy it into the directory indicated by the
OUTPUT_DIR environment variable before your run finishes (for example, run
`cp local_path "$OUTPUT_DIR/"`). After you finish creating an artifact, call
the bash tool to copy the exact output into "$OUTPUT_DIR" (for example, send a
command like `cp /tmp/output.ext "$OUTPUT_DIR/output.ext" && ls "$OUTPUT_DIR"`).
Only files placed in OUTPUT_DIR are returned to the caller. Confirm the copied
file names in your final response.
"""),
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
      final mapped = await _mapChunk(chunk, tracker);
      yield mapped;
    }
  }

  @override
  void dispose() {
    _chatModel.dispose();
    _filesClient.close();
  }

  Future<MediaGenerationResult> _mapChunk(
    ChatResult<ChatMessage> result,
    AnthropicToolDeliverableTracker tracker,
  ) async {
    _logger.fine('Processing Anthropic chunk for result id ${result.id}');
    if (result.metadata.isNotEmpty) {
      _logger.finer('Anthropic chunk metadata: ${result.metadata}');
    }
    final assets = <Part>[];
    final links = <LinkPart>[];
    final metadata = Map<String, dynamic>.from(result.metadata);

    assets.addAll(tracker.collectMessageAssets(result.messages));
    links.addAll(tracker.collectMessageLinks(result.messages));

    final metadataDeliverables = await tracker.handleMetadata(result.metadata);
    assets.addAll(metadataDeliverables.assets);
    links.addAll(metadataDeliverables.links);
    final isComplete = result.finishReason != FinishReason.unspecified;

    if (isComplete && assets.isEmpty) {
      final remoteAssets = await tracker.collectRecentFiles();
      assets.addAll(remoteAssets);
    }

    if (isComplete && assets.isEmpty) {
      _logger.warning(
        'Anthropic media generation completed without downloadable assets.',
      );
    }

    if (isComplete) {
      _logger.fine(
        'Anthropic media generation completed with ${assets.length} assets '
        'and ${links.length} links',
      );
      final toolMetadata = tracker.buildToolMetadata();
      for (final entry in toolMetadata.entries) {
        metadata[entry.key] = entry.value;
      }
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
    AnthropicMediaGenerationModelOptions base,
    AnthropicMediaGenerationModelOptions? override,
  ) {
    final mergedServerTools = <AnthropicServerToolConfig>[
      ...?base.serverTools,
      ...?override?.serverTools,
    ];

    return _ResolvedAnthropicMediaSettings(
      maxTokens: override?.maxTokens ?? base.maxTokens ?? 4096,
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
      toolChoice: const AnthropicToolChoice.auto(),
    );
  }

  String _augmentPrompt(String prompt, List<String> mimeTypes) {
    if (prompt.trim().isEmpty) return prompt;
    const guidance = r'''

Use the available code execution tool to programmatically create the requested
files. Create any helper scripts in the text editor tool, then execute them
with the shell tool (for example, by running `python /tmp/create_file.py`) so
the artifacts are actually produced. When a PDF is required, generate it with
Python (installing libraries such as reportlab if needed). If the reportlab
module is missing, first try `pip install --quiet reportlab`; when that is not
available, fall back to libraries that are already installed (for example,
PyMuPDF/fitz or pypdf) or emit a minimal PDF by writing the raw PDF structure
yourself. Do not finish until the PDF exists. Run the script to build the PDF,
confirm the file exists, and then return it. For text artifacts, write the
content to a file (e.g., using `cat` or Python). After you save a file, execute
a shell command such as `cp /tmp/output.ext "$OUTPUT_DIR/output.ext"` so the
artifact is available for download before you finish. Always verify the copy by
listing the directory (for example, `ls "$OUTPUT_DIR"`).
''';
    if (prompt.contains('code execution tool')) return prompt;
    return '$prompt$guidance';
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
