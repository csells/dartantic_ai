#!/bin/bash
# SC-004: Use a model string directly as the agent
echo "Using model string as agent:"
echo '$ dartantic -a "openai:gpt-4o-mini" -p "Hello!"'
dart run bin/dartantic.dart -a "openai:gpt-4o-mini" -p "Hello!"
