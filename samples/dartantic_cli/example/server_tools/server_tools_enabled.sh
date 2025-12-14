#!/bin/bash
# SC-025: Server-side tools enabled by default
echo "Server-side tools (enabled by default):"
echo '$ dartantic -a anthropic -p "Hello"'
dart run bin/dartantic.dart -a anthropic -p "Hello"
