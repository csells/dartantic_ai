#!/bin/bash
# SC-059/SC-060: Environment variable configuration
echo "Using DARTANTIC_AGENT environment variable:"
echo '$ DARTANTIC_AGENT=anthropic dartantic -p "Hello"'
DARTANTIC_AGENT=anthropic dart run bin/dartantic.dart -p "Say hello."

echo ""
echo "Using DARTANTIC_LOG_LEVEL for debugging:"
echo '$ DARTANTIC_LOG_LEVEL=INFO dartantic -p "Hello"'
DARTANTIC_LOG_LEVEL=INFO dart run bin/dartantic.dart -p "Say hello again."
