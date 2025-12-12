#!/bin/bash
# Using different AI providers
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
echo "Using Google (default):"
echo '$ dartantic -p "Name a color."'
dart run bin/dartantic.dart -p "Name a color."

echo -e "\nUsing Anthropic:"
echo '$ dartantic -a anthropic -p "Name a fruit."'
dart run bin/dartantic.dart -a anthropic -p "Name a fruit."

echo -e "\nUsing OpenAI:"
echo '$ dartantic -a openai:gpt-4o-mini -p "Name a planet."'
dart run bin/dartantic.dart -a openai:gpt-4o-mini -p "Name a planet."
