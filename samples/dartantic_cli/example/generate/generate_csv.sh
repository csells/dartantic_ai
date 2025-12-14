#!/bin/bash
# SC-038: Generate CSV file
# Note: Requires openai-responses provider
mkdir -p tmp/generated

echo "Generate CSV:"
echo '$ dartantic generate -a openai-responses --mime text/csv -p "5 rows of sample user data" -o tmp/generated'
dart run bin/dartantic.dart generate -a openai-responses --mime text/csv \
  -p "5 rows of sample user data" -o tmp/generated
