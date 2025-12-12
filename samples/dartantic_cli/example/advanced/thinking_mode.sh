#!/bin/bash
# See model's reasoning process
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
echo "Thinking mode (shows reasoning with Gemini):"
echo '$ dartantic -a google:gemini-2.5-flash -p "Think step by step: what is 15 * 23?"'
dart run bin/dartantic.dart -a google:gemini-2.5-flash -p "Think step by step: what is 15 * 23?"
