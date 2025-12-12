#!/bin/bash
# Using a custom agent from settings
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
echo "Using custom 'coder' agent from settings:"
echo '$ dartantic -s "agents.yaml" -a coder -p "Write a one-line Python function to add two numbers."'
dart run bin/dartantic.dart -s "$SCRIPT_DIR/../resources/settings/agents.yaml" -a coder -p "Write a one-line Python function to add two numbers."
