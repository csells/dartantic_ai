#!/bin/bash
# SC-039: Generate multiple MIME types
mkdir -p tmp/generated

echo "Generate multiple types:"
echo '$ dartantic generate -a google --mime image/png --mime image/jpeg -p "A simple blue square logo" -o tmp/generated'
dart run bin/dartantic.dart generate -a google --mime image/png --mime image/jpeg \
  -p "A simple blue square logo" -o tmp/generated
