import 'package:dartantic_interface/dartantic_interface.dart';
import 'package:logging/logging.dart';

/// Firebase AI specific options for thinking/reasoning mode.
class FirebaseAIThinkingOptions {
  /// Creates Firebase AI thinking options.
  const FirebaseAIThinkingOptions({
    this.enabled = false,
    this.includeReasoningSteps = true,
    this.includeSafetyAnalysis = true,
    this.verboseCitationMetadata = false,
  });

  /// Whether to enable thinking mode detection.
  final bool enabled;

  /// Whether to include reasoning steps in metadata.
  final bool includeReasoningSteps;

  /// Whether to include safety analysis in thinking output.
  final bool includeSafetyAnalysis;

  /// Whether to include verbose citation metadata in thinking.
  final bool verboseCitationMetadata;
}

/// Utilities for handling Firebase AI thinking/reasoning mode.
class FirebaseAIThinkingUtils {
  static final Logger _logger = Logger(
    'dartantic.chat.models.firebase_ai.thinking',
  );

  /// Extracts thinking/reasoning content from Firebase AI metadata.
  static String? extractThinking(
    ChatResult<ChatMessage> result, {
    FirebaseAIThinkingOptions options = const FirebaseAIThinkingOptions(),
  }) {
    if (!options.enabled) return null;

    final buffer = StringBuffer();
    var hasContent = false;

    try {
      // Extract safety analysis if requested
      if (options.includeSafetyAnalysis) {
        final safetyRatings = result.metadata['safety_ratings'] as List?;
        if (safetyRatings != null && safetyRatings.isNotEmpty) {
          buffer.writeln('[SAFETY ANALYSIS]');
          for (final rating in safetyRatings) {
            if (rating is Map<String, dynamic>) {
              final category = rating['category'] as String?;
              final probability = rating['probability'] as String?;
              if (category != null && probability != null) {
                buffer.writeln('- $category: $probability');
              }
            }
          }
          buffer.writeln();
          hasContent = true;
        }
      }

      // Extract reasoning steps from block_reason and finish_message
      if (options.includeReasoningSteps) {
        final blockReason = result.metadata['block_reason'] as String?;
        final blockReasonMessage = result.metadata['block_reason_message'] as String?;
        final finishMessage = result.metadata['finish_message'] as String?;

        if (blockReason != null || blockReasonMessage != null) {
          buffer.writeln('[CONTENT FILTERING REASONING]');
          if (blockReason != null) {
            buffer.writeln('Block Reason: $blockReason');
          }
          if (blockReasonMessage != null) {
            buffer.writeln('Reasoning: $blockReasonMessage');
          }
          buffer.writeln();
          hasContent = true;
        }

        if (finishMessage != null && finishMessage.isNotEmpty) {
          buffer.writeln('[COMPLETION REASONING]');
          buffer.writeln(finishMessage);
          buffer.writeln();
          hasContent = true;
        }
      }

      // Extract citation metadata if requested
      if (options.verboseCitationMetadata) {
        final citationMetadata = result.metadata['citation_metadata'] as String?;
        if (citationMetadata != null && citationMetadata.isNotEmpty) {
          buffer.writeln('[CITATION ANALYSIS]');
          buffer.writeln(citationMetadata);
          buffer.writeln();
          hasContent = true;
        }
      }

      // Extract any explicit reasoning from model output patterns
      final modelMessage = result.output;
      final reasoningPatterns = _extractReasoningPatterns(modelMessage);
      if (reasoningPatterns.isNotEmpty) {
        buffer.writeln('[DETECTED REASONING PATTERNS]');
        for (final pattern in reasoningPatterns) {
          buffer.writeln('- $pattern');
        }
        buffer.writeln();
        hasContent = true;
      }

      if (hasContent) {
        _logger.fine(
          'Extracted thinking content: ${buffer.length} characters',
        );
        return buffer.toString().trim();
      }

      return null;
    } catch (e, stackTrace) {
      _logger.warning(
        'Error extracting thinking content: $e',
        e,
        stackTrace,
      );
      return null;
    }
  }

  /// Extracts reasoning patterns from model output.
  static List<String> _extractReasoningPatterns(ChatMessage message) {
    final patterns = <String>[];
    
    for (final part in message.parts) {
      if (part is TextPart) {
        final text = part.text;
        
        // Look for explicit reasoning markers
        final reasoningMarkers = [
          'Let me think',
          'First, I need to',
          'The reason is',
          'This is because',
          'I need to consider',
          'Let me analyze',
          'Step by step',
          'My reasoning',
        ];
        
        for (final marker in reasoningMarkers) {
          if (text.toLowerCase().contains(marker.toLowerCase())) {
            // Extract the sentence containing the reasoning marker
            final sentences = text.split(RegExp('[.!?]'));
            for (final sentence in sentences) {
              if (sentence.toLowerCase().contains(marker.toLowerCase())) {
                patterns.add('$marker: ${sentence.trim()}');
                break;
              }
            }
          }
        }
      }
    }
    
    return patterns;
  }

  /// Creates a ChatResult with thinking metadata added.
  static ChatResult<ChatMessage> addThinkingMetadata(
    ChatResult<ChatMessage> result,
    FirebaseAIThinkingOptions options,
  ) {
    if (!options.enabled) return result;

    final thinking = extractThinking(result, options: options);
    if (thinking == null) return result;

    final updatedMetadata = <String, dynamic>{
      ...result.metadata,
      'thinking': thinking,
    };

    return ChatResult<ChatMessage>(
      id: result.id,
      output: result.output,
      messages: result.messages,
      finishReason: result.finishReason,
      metadata: updatedMetadata,
      usage: result.usage,
    );
  }
}