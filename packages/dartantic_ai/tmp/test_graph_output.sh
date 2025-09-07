#!/bin/bash

echo "Testing Code Interpreter with graph generation..."
echo ""

OPENAI_API_KEY=$(grep OPENAI_API_KEY ~/global_env.sh | cut -d'"' -f2)

# Test with a request that should generate a graph
curl -X POST https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Accept: text/event-stream" \
  -N \
  -d '{
    "model": "gpt-4o",
    "stream": true,
    "instructions": "You are a data visualization expert. Always create graphs when asked.",
    "input": "Create a simple bar chart showing values [10, 20, 15, 25, 30] with labels A, B, C, D, E",
    "tools": [{"type": "code_interpreter", "container": {"type": "auto"}}]
  }' 2>/dev/null | grep -E "image|output|file|url|attachment|result" | head -100