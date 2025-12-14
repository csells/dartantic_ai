#!/bin/bash
# SC-042: Create embeddings for multiple files
mkdir -p tmp
echo "Python is great for data science." > tmp/doc1.txt
echo "JavaScript runs in browsers." > tmp/doc2.txt
echo "Rust is memory safe." > tmp/doc3.txt

echo "Embed multiple files:"
echo '$ dartantic embed create tmp/doc1.txt tmp/doc2.txt tmp/doc3.txt > tmp/multi_embeddings.json'
dart run bin/dartantic.dart embed create tmp/doc1.txt tmp/doc2.txt tmp/doc3.txt > tmp/multi_embeddings.json
echo "Embeddings saved to tmp/multi_embeddings.json"
