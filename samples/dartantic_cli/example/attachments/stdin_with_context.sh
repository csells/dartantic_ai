#!/bin/bash
# SC-012: Chat from stdin with file context
mkdir -p tmp
echo "The secret number is 42." > tmp/context.txt

echo "Stdin with file context:"
echo '$ dartantic -p "What is the secret number? @tmp/context.txt"'
dart run bin/dartantic.dart -p "What is the secret number? @tmp/context.txt"
