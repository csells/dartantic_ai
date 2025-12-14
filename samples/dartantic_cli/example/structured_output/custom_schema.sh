#!/bin/bash
# SC-018: Using a schema file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Using schema file for structured output:"
echo '$ dartantic -p "Tell me about Tokyo." --output-schema "@resources/schemas/city.json"'
dart run bin/dartantic.dart -p "Tell me about Tokyo." \
  --output-schema "@$SCRIPT_DIR/../resources/schemas/city.json"
