#!/bin/bash
# SC-035/SC-040: Generate image with specific provider
OUTPUT_DIR="tmp"
mkdir -p "$OUTPUT_DIR"

echo "Generating an image:"
echo '$ dartantic generate -a google --mime image/png -o tmp -p "A simple red circle"'
dart run bin/dartantic.dart generate -a google --mime image/png -o "$OUTPUT_DIR" -p "A simple red circle on white background"
