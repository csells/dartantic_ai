#!/bin/bash
# SC-061: Provider API key from environment
# Uses OPENAI_API_KEY from environment
echo "Using provider API key from environment:"
echo '$ dartantic -a openai -p "Hello"'
dart run bin/dartantic.dart -a openai -p "Hello"
