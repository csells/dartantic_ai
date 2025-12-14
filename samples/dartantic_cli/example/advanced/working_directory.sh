#!/bin/bash
# SC-032: Working directory override
mkdir -p tmp/workdir
echo "The secret word is APPLE." > tmp/workdir/local.txt

echo "Using working directory override:"
echo '$ dartantic -d tmp/workdir -p "What is the secret word? @local.txt"'
dart run bin/dartantic.dart -d tmp/workdir -p "What is the secret word? Reply with just the word. @local.txt"
