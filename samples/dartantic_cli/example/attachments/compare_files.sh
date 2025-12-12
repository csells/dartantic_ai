#!/bin/bash
# Compare multiple files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Comparing two files:"
echo '$ dartantic -p "What are the key differences between these two files? @resources/files/sample.txt @resources/files/notes.txt"'
dart run bin/dartantic.dart -p "What are the key differences between these two files? @$SCRIPT_DIR/../resources/files/sample.txt @$SCRIPT_DIR/../resources/files/notes.txt"
