#!/bin/bash
# Get structured JSON output
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../.."
echo "Getting JSON response:"
echo '$ dartantic -p "List 3 programming languages." --output-schema '"'"'{"type":"object","properties":{"languages":{"type":"array","items":{"type":"string"}}},"required":["languages"]}'"'"''
dart run bin/dartantic.dart -p "List 3 programming languages." \
  --output-schema '{"type":"object","properties":{"languages":{"type":"array","items":{"type":"string"}}},"required":["languages"]}'
