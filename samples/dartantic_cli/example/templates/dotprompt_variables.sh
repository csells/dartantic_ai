#!/bin/bash
# Override template variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Running template with custom variable:"
dart run bin/dartantic.dart -p "@$SCRIPT_DIR/../resources/prompts/math.prompt" number=99
