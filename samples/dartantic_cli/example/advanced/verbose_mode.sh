#!/bin/bash
# SC-021: Show token usage statistics
echo "Verbose mode (shows token usage on stderr):"
echo '$ dartantic -v -p "What is the speed of light?"'
dart run bin/dartantic.dart -v -p "What is the speed of light?"
