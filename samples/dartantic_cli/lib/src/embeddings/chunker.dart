/// Text chunking utility for embeddings.
///
/// Splits text into smaller chunks suitable for embedding generation,
/// using a hierarchy of paragraph → sentence → token-based splitting.
class TextChunker {
  /// Creates a text chunker with specified chunk parameters.
  ///
  /// - [chunkSize]: Target size in characters (not tokens, for simplicity)
  /// - [overlap]: Number of overlapping characters between chunks
  TextChunker({
    this.chunkSize = 512,
    this.overlap = 100,
  });

  /// Target chunk size in characters.
  final int chunkSize;

  /// Overlap between consecutive chunks in characters.
  final int overlap;

  /// Splits text into chunks, returning a list of [Chunk] objects.
  ///
  /// The algorithm:
  /// 1. Split at paragraph boundaries (double newline)
  /// 2. If a paragraph exceeds [chunkSize], split at sentence boundaries
  /// 3. If a sentence exceeds [chunkSize], split with overlap
  List<Chunk> chunk(String text) {
    final chunks = <Chunk>[];
    if (text.isEmpty) return chunks;

    // Split into paragraphs (double newline or paragraph markers)
    final paragraphs = _splitParagraphs(text);

    var currentOffset = 0;
    for (final paragraph in paragraphs) {
      if (paragraph.isEmpty) {
        currentOffset += 2; // Account for \n\n
        continue;
      }

      final paragraphChunks = _chunkParagraph(paragraph, currentOffset);
      chunks.addAll(paragraphChunks);
      currentOffset += paragraph.length + 2; // +2 for \n\n separator
    }

    return chunks;
  }

  /// Splits text into paragraphs.
  List<String> _splitParagraphs(String text) {
    return text.split(RegExp(r'\n\s*\n'));
  }

  /// Chunks a single paragraph, splitting at sentences if needed.
  List<Chunk> _chunkParagraph(String paragraph, int startOffset) {
    final chunks = <Chunk>[];

    if (paragraph.length <= chunkSize) {
      // Paragraph fits in one chunk
      chunks.add(Chunk(text: paragraph.trim(), offset: startOffset));
    } else {
      // Split at sentence boundaries
      final sentences = _splitSentences(paragraph);
      var currentChunk = StringBuffer();
      var chunkStartOffset = startOffset;
      var sentenceOffset = 0;

      for (final sentence in sentences) {
        final trimmedSentence = sentence.trim();
        if (trimmedSentence.isEmpty) continue;

        if (currentChunk.isEmpty) {
          // Start new chunk
          if (trimmedSentence.length > chunkSize) {
            // Single sentence too long, split with overlap
            chunks.addAll(_splitWithOverlap(
              trimmedSentence,
              startOffset + sentenceOffset,
            ));
          } else {
            currentChunk.write(trimmedSentence);
            chunkStartOffset = startOffset + sentenceOffset;
          }
        } else if (currentChunk.length + 1 + trimmedSentence.length <=
            chunkSize) {
          // Add to current chunk
          currentChunk
            ..write(' ')
            ..write(trimmedSentence);
        } else {
          // Finalize current chunk, start new one
          chunks.add(Chunk(
            text: currentChunk.toString(),
            offset: chunkStartOffset,
          ));

          if (trimmedSentence.length > chunkSize) {
            chunks.addAll(_splitWithOverlap(
              trimmedSentence,
              startOffset + sentenceOffset,
            ));
            currentChunk.clear();
          } else {
            currentChunk
              ..clear()
              ..write(trimmedSentence);
            chunkStartOffset = startOffset + sentenceOffset;
          }
        }

        sentenceOffset += sentence.length;
      }

      // Don't forget remaining content
      if (currentChunk.isNotEmpty) {
        chunks.add(Chunk(
          text: currentChunk.toString(),
          offset: chunkStartOffset,
        ));
      }
    }

    return chunks;
  }

  /// Splits text into sentences.
  List<String> _splitSentences(String text) {
    // Split on sentence-ending punctuation followed by space or end
    final sentencePattern = RegExp(r'(?<=[.!?])\s+');
    return text.split(sentencePattern);
  }

  /// Splits text with overlap when it's too long.
  List<Chunk> _splitWithOverlap(String text, int startOffset) {
    final chunks = <Chunk>[];
    var position = 0;

    while (position < text.length) {
      final end = (position + chunkSize).clamp(0, text.length);
      final chunkText = text.substring(position, end).trim();

      if (chunkText.isNotEmpty) {
        chunks.add(Chunk(text: chunkText, offset: startOffset + position));
      }

      if (end >= text.length) break;

      // Move forward by chunkSize minus overlap
      position += chunkSize - overlap;
      if (position >= text.length) break;
    }

    return chunks;
  }
}

/// Represents a chunk of text with its offset in the original document.
class Chunk {
  /// Creates a chunk with text and offset.
  const Chunk({required this.text, required this.offset});

  /// The chunk text content.
  final String text;

  /// Offset (in characters) from the start of the original document.
  final int offset;

  @override
  String toString() => 'Chunk(offset: $offset, text: "${text.substring(
        0,
        text.length > 50 ? 50 : text.length,
      )}...")';
}
