#!/bin/bash
# Analyze an attached file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
echo "Analyzing attached file:"
echo '$ dartantic -p "Summarize the content of this file in one sentence. @resources/files/sample.txt"'
dart run bin/dartantic.dart -p "Summarize the content of this file in one sentence. @$SCRIPT_DIR/../resources/files/sample.txt"
