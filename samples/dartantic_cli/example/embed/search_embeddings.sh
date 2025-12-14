#!/bin/bash
# SC-045/SC-046/SC-047: Search embeddings
OUTPUT_DIR="tmp"
EMBEDDINGS_FILE="$OUTPUT_DIR/embeddings.json"

# First create embeddings if they don't exist
if [ ! -f "$EMBEDDINGS_FILE" ]; then
    echo "Creating embeddings first..."
    bash "$(dirname "$0")/create_embeddings.sh"
fi

echo "Searching embeddings:"
echo '$ dartantic embed search -q "Flutter development" embeddings.json'
dart run bin/dartantic.dart embed search -q "Flutter development" "$EMBEDDINGS_FILE"

echo ""
echo "Search with verbose output:"
echo '$ dartantic -v embed search -q "Dart programming" embeddings.json'
dart run bin/dartantic.dart -v embed search -q "Dart programming" "$EMBEDDINGS_FILE"
