#!/bin/bash
# SC-020: Chat with temperature setting
echo "Using temperature for creativity:"
echo '$ dartantic -t 0.9 -p "Write a creative story opening in one sentence"'
dart run bin/dartantic.dart -t 0.9 -p "Write a creative story opening in one sentence"
