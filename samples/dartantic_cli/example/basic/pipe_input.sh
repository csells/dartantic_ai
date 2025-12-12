#!/bin/bash
# Pipe input to the CLI
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
echo "Piping a question:"
echo '$ echo "What is the capital of Japan? Reply with just the city name." | dartantic'
echo "What is the capital of Japan? Reply with just the city name." | dart run bin/dartantic.dart
