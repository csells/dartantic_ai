#!/bin/bash
# Override template variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
echo "Running template with custom variable:"
echo '$ dartantic -p "@resources/prompts/math.prompt" number=99'
dart run bin/dartantic.dart -p "@$SCRIPT_DIR/../resources/prompts/math.prompt" number=99
