#!/bin/bash
# Analyze an attached file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Analyzing attached file:"
dart run bin/dartantic.dart -p "Summarize the content of this file in one sentence. @$SCRIPT_DIR/../resources/files/sample.txt"
