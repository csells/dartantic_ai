#!/bin/bash
# SC-010: Chat with image attachment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Sending an image for analysis:"
echo '$ dartantic -a google -p "Describe this image briefly. @image_0.png"'
dart run "$CLI_DIR/bin/dartantic.dart" -a google -p "Describe this image briefly. @$CLI_DIR/image_0.png"
