#!/bin/bash
# Using a .prompt template file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Running a .prompt template (uses default variable):"
echo '$ dartantic -p "@resources/prompts/math.prompt"'
dart run bin/dartantic.dart -p "@$SCRIPT_DIR/../resources/prompts/math.prompt"
