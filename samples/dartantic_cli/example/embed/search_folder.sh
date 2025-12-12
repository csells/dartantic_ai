#!/bin/bash
# SC-046: Search embeddings in a folder
OUTPUT_DIR="tmp"
EMBEDDINGS_DIR="$OUTPUT_DIR/embeddings_folder"
mkdir -p "$EMBEDDINGS_DIR"

# Create embeddings and save to folder
echo "Creating embeddings..."
echo "Python is great for data science." > "$OUTPUT_DIR/python.txt"
dart run bin/dartantic.dart embed create "$OUTPUT_DIR/python.txt" > "$EMBEDDINGS_DIR/embeddings.json"

echo "Searching in folder:"
echo '$ dartantic embed search -q "data science" tmp/embeddings_folder/'
dart run bin/dartantic.dart embed search -q "data science" "$EMBEDDINGS_DIR/"
