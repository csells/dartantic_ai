#!/bin/bash
# SC-047: Search embeddings with verbose output
mkdir -p tmp
echo "Python is great for data science." > tmp/verbose_doc.txt
dart run bin/dartantic.dart embed create tmp/verbose_doc.txt > tmp/verbose_embeddings.json

echo "Search with verbose output:"
echo '$ dartantic embed search -v -q "data science" tmp/verbose_embeddings.json'
dart run bin/dartantic.dart embed search -v -q "data science" tmp/verbose_embeddings.json
