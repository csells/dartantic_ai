#!/bin/bash
# Get structured JSON output
echo "Getting JSON response:"
dart run bin/dartantic.dart -p "List 3 programming languages." \
  --output-schema '{"type":"object","properties":{"languages":{"type":"array","items":{"type":"string"}}},"required":["languages"]}'
