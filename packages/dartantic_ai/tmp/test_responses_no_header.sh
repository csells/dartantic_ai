#!/bin/bash

echo "Testing Responses API WITHOUT beta header..."
echo ""

OPENAI_API_KEY=$(grep OPENAI_API_KEY ~/global_env.sh | cut -d'"' -f2)

# Test without the beta header
curl -X POST https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4o",
    "instructions": "You are a helpful assistant",
    "input": "Say hello"
  }'