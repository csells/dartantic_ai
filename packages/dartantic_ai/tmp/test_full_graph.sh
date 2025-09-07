#!/bin/bash

echo "Testing full graph generation flow..."
echo ""

OPENAI_API_KEY=$(grep OPENAI_API_KEY ~/global_env.sh | cut -d'"' -f2)

# Test with simple graph request and capture ALL events
curl -X POST https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Accept: text/event-stream" \
  -N \
  -d '{
    "model": "gpt-4o",
    "stream": true,
    "instructions": "Create a graph using matplotlib",
    "input": "Plot y = x^2 for x from 0 to 10",
    "tools": [{"type": "code_interpreter", "container": {"type": "auto"}}]
  }' 2>/dev/null