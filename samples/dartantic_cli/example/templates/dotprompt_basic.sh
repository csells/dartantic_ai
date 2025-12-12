#!/bin/bash
# Using a .prompt template file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
echo "Running a .prompt template (uses default variable):"
echo '$ dartantic -p "@resources/prompts/math.prompt"'
dart run bin/dartantic.dart -p "@$SCRIPT_DIR/../resources/prompts/math.prompt"
