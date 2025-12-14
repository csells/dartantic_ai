#!/bin/bash
# SC-041/SC-043: Create embeddings from files
OUTPUT_DIR="tmp"
mkdir -p "$OUTPUT_DIR"

# Create test documents
echo "Dart is a programming language for building apps." > "$OUTPUT_DIR/doc1.txt"
echo "Flutter uses Dart for cross-platform development." > "$OUTPUT_DIR/doc2.txt"

echo "Creating embeddings from files:"
echo '$ dartantic embed create doc1.txt doc2.txt'
dart run bin/dartantic.dart embed create "$OUTPUT_DIR/doc1.txt" "$OUTPUT_DIR/doc2.txt" > "$OUTPUT_DIR/embeddings.json"

echo "Embeddings saved to $OUTPUT_DIR/embeddings.json"
