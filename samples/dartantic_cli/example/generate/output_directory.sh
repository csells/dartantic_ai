#!/bin/bash
# SC-036: Generate with output directory
mkdir -p tmp/generated

echo "Generate image to output directory:"
echo '$ dartantic generate --mime image/png -p "A sunset" -o tmp/generated'
dart run bin/dartantic.dart generate --mime image/png -p "A sunset" -o tmp/generated
