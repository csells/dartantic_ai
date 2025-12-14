#!/bin/bash
# SC-049: List models for specific provider
echo "List OpenAI models:"
echo '$ dartantic -a openai models'
dart run bin/dartantic.dart -a openai models | head -20
