#!/bin/bash
# Using different AI providers
echo "Using Google (default):"
dart run bin/dartantic.dart -p "Name a color."

echo -e "\nUsing Anthropic:"
dart run bin/dartantic.dart -a anthropic -p "Name a fruit."

echo -e "\nUsing OpenAI:"
dart run bin/dartantic.dart -a openai:gpt-4o-mini -p "Name a planet."
