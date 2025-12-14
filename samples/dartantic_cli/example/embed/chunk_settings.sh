#!/bin/bash
# SC-044: Create embeddings with custom chunk size
mkdir -p tmp
echo "This is a test document with some content for chunking. " > tmp/chunk_doc.txt
for i in {1..10}; do echo "More content line $i." >> tmp/chunk_doc.txt; done

echo "Embed with custom chunk settings:"
echo '$ dartantic embed create --chunk-size 256 --chunk-overlap 50 tmp/chunk_doc.txt > tmp/small_chunks.json'
dart run bin/dartantic.dart embed create --chunk-size 256 --chunk-overlap 50 tmp/chunk_doc.txt > tmp/small_chunks.json
echo "Embeddings saved to tmp/small_chunks.json"
