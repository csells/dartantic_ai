import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

/// Accumulates streaming Firebase AI results into a final consolidated result.
///
/// Handles accumulation of output text, messages, metadata (including Firebase-specific
/// data like safety ratings, citations), and usage statistics from streaming chunks
/// into a final ChatResult.
class FirebaseAIStreamingAccumulator {
  /// Creates a new Firebase AI streaming accumulator.
  FirebaseAIStreamingAccumulator({required this.modelName});

  /// The model name for logging and debugging.
  final String modelName;

  static final Logger _logger = Logger(
    'dartantic.chat.models.firebase_ai.streaming_accumulator',
  );

  final List<ChatMessage> _allNewMessages = <ChatMessage>[];
  final StringBuffer _finalOutputBuffer = StringBuffer();
  final StringBuffer _thinkingBuffer = StringBuffer();
  final Map<String, dynamic> _accumulatedMetadata = <String, dynamic>{};
  final List<Map<String, dynamic>> _allSafetyRatings = <Map<String, dynamic>>[];
  final List<String> _allCitations = <String>[];

  ChatResult<ChatMessage> _finalResult = ChatResult<ChatMessage>(
    output: const ChatMessage(role: ChatMessageRole.model, parts: []),
    messages: const [],
    finishReason: FinishReason.unspecified,
    metadata: const <String, dynamic>{},
    usage: null,
  );

  int _chunkCount = 0;

  /// Adds a streaming result chunk to the accumulator.
  void add(ChatResult<ChatMessage> result) {
    _chunkCount++;
    _logger.fine(
      'Accumulating Firebase AI chunk $_chunkCount for model $modelName',
    );

    try {
      // Accumulate output text from message parts
      if (result.output.parts.isNotEmpty) {
        for (final part in result.output.parts) {
          if (part is TextPart && part.text.isNotEmpty) {
            _finalOutputBuffer.write(part.text);
          }
        }
      }

      // Accumulate messages
      _allNewMessages.addAll(result.messages);

      // Store the latest result for final metadata/usage/finishReason
      _finalResult = result;

      // Accumulate Firebase-specific thinking/reasoning content
      final thinking = result.metadata['thinking'] as String?;
      if (thinking != null && thinking.isNotEmpty) {
        _thinkingBuffer.write(thinking);
        _logger.fine(
          'Accumulated thinking content: ${thinking.length} chars',
        );
      }

      // Accumulate safety ratings
      final safetyRatings = result.metadata['safety_ratings'] as List?;
      if (safetyRatings != null) {
        _allSafetyRatings.addAll(
          safetyRatings.cast<Map<String, dynamic>>(),
        );
      }

      // Accumulate citation metadata
      final citationMetadata = result.metadata['citation_metadata'] as String?;
      if (citationMetadata != null && !_allCitations.contains(citationMetadata)) {
        _allCitations.add(citationMetadata);
      }

      // Merge other metadata (preserving response-level info from final chunk)
      for (final entry in result.metadata.entries) {
        if (!{'thinking', 'safety_ratings', 'citation_metadata'}.contains(entry.key)) {
          _accumulatedMetadata[entry.key] = entry.value;
        }
      }
    } catch (e, stackTrace) {
      _logger.severe(
        'Error accumulating Firebase AI chunk $_chunkCount: $e',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Builds the final accumulated ChatResult.
  ChatResult<ChatMessage> buildFinal() {
    _logger.fine(
      'Building final Firebase AI result from $_chunkCount chunks '
      'for model $modelName',
    );

    try {
      // Build final metadata with all accumulated data
      final mergedMetadata = <String, dynamic>{
        ..._accumulatedMetadata,
        if (_thinkingBuffer.isNotEmpty) 'thinking': _thinkingBuffer.toString(),
        if (_allSafetyRatings.isNotEmpty) 'safety_ratings': _allSafetyRatings,
        if (_allCitations.isNotEmpty) 'citation_metadata': _allCitations.join('; '),
        'chunk_count': _chunkCount,
      };

      // Create final output message with accumulated text
      final finalOutput = ChatMessage(
        role: ChatMessageRole.model,
        parts: _finalOutputBuffer.isNotEmpty
            ? [TextPart(_finalOutputBuffer.toString())]
            : [],
      );

      final result = ChatResult<ChatMessage>(
        id: _finalResult.id,
        output: finalOutput,
        messages: _allNewMessages.isNotEmpty ? _allNewMessages : [finalOutput],
        finishReason: _finalResult.finishReason,
        metadata: mergedMetadata,
        usage: _finalResult.usage,
      );

      _logger.info(
        'Built final Firebase AI result: '
        'output=${_finalOutputBuffer.length} chars, '
        'messages=${_allNewMessages.length}, '
        'thinking=${_thinkingBuffer.length} chars, '
        'chunks=$_chunkCount',
      );

      return result;
    } catch (e, stackTrace) {
      _logger.severe(
        'Error building final Firebase AI result: $e',
        e,
        stackTrace,
      );
      rethrow;
    }
  }

  /// Returns the current accumulated text length.
  int get accumulatedTextLength => _finalOutputBuffer.length;

  /// Returns the number of chunks processed.
  int get chunkCount => _chunkCount;

  /// Returns true if any thinking content has been accumulated.
  bool get hasThinking => _thinkingBuffer.isNotEmpty;

  /// Returns true if any safety ratings have been accumulated.
  bool get hasSafetyRatings => _allSafetyRatings.isNotEmpty;
}