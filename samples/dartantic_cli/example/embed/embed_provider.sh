#!/bin/bash
# SC-043: Create embeddings with specific provider
mkdir -p tmp
echo "Test content for OpenAI embeddings." > tmp/openai_doc.txt

echo "Embed with specific provider:"
echo '$ dartantic -a openai embed create tmp/openai_doc.txt > tmp/openai_embeddings.json'
dart run bin/dartantic.dart -a openai embed create tmp/openai_doc.txt > tmp/openai_embeddings.json
echo "Embeddings saved to tmp/openai_embeddings.json"
