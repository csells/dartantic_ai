#!/bin/bash
# Show token usage statistics
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
echo "Verbose mode (shows token usage on stderr):"
echo '$ dartantic -v -p "What is the speed of light?"'
dart run bin/dartantic.dart -v -p "What is the speed of light?"
