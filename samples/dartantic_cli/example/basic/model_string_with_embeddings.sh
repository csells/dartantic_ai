#!/bin/bash
# SC-005: Full model string with embeddings configuration
echo "Using full model string with chat and embeddings:"
echo '$ dartantic -a "openai?chat=gpt-4o-mini&embeddings=text-embedding-3-small" -p "What is 4+4?"'
dart run bin/dartantic.dart -a "openai?chat=gpt-4o-mini&embeddings=text-embedding-3-small" -p "What is 4+4? Reply with just the number."
