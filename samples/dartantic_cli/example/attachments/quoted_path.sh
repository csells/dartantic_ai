#!/bin/bash
# SC-009: File attachment with quotes around whole path
mkdir -p tmp
echo "The secret word is ORANGE." > "tmp/another file.txt"

echo "Attaching file with spaces (quotes around whole thing):"
echo '$ dartantic -p "What is the secret word? \"@tmp/another file.txt\""'
dart run bin/dartantic.dart -p "What is the secret word? Reply with just the word. \"@tmp/another file.txt\""
