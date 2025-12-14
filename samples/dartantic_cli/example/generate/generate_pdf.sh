#!/bin/bash
# SC-037: Generate PDF document
# Note: Requires openai-responses provider
mkdir -p tmp/generated

echo "Generate PDF:"
echo '$ dartantic generate -a openai-responses --mime application/pdf -p "A report about AI" -o tmp/generated'
dart run bin/dartantic.dart generate -a openai-responses --mime application/pdf \
  -p "A report about AI" -o tmp/generated
