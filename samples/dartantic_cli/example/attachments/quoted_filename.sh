#!/bin/bash
# SC-008: File attachment with quoted filename (spaces in name)
mkdir -p tmp
echo "The secret word is BANANA." > "tmp/my file.txt"

echo "Attaching file with spaces (quotes after @):"
echo '$ dartantic -p "What is the secret word in this file? @\"tmp/my file.txt\""'
dart run bin/dartantic.dart -p "What is the secret word in this file? Reply with just the word. @\"tmp/my file.txt\""
