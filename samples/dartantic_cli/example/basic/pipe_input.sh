#!/bin/bash
# SC-011: Pipe input to the CLI
echo "Piping a question:"
echo '$ echo "What is the capital of Japan? Reply with just the city name." | dartantic'
echo "What is the capital of Japan? Reply with just the city name." | dart run bin/dartantic.dart
