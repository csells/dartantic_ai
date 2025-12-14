#!/bin/bash
# SC-040: Generate with specific provider
mkdir -p tmp/generated

echo "Generate with specific provider:"
echo '$ dartantic generate -a google --mime image/png -p "A mountain landscape" -o tmp/generated'
dart run bin/dartantic.dart generate -a google --mime image/png -p "A mountain landscape" -o tmp/generated
