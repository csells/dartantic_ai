#!/bin/bash
# Simple question and answer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
echo "Ask a simple math question:"
echo '$ dartantic -p "What is 2+2? Reply with just the number."'
dart run bin/dartantic.dart -p "What is 2+2? Reply with just the number."
