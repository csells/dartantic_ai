#!/bin/bash

echo "Testing Code Interpreter with streaming to see container_id..."
echo ""

OPENAI_API_KEY=$(grep OPENAI_API_KEY ~/global_env.sh | cut -d'"' -f2)

# Test with streaming to see all events
curl -X POST https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Accept: text/event-stream" \
  -N \
  -d '{
    "model": "gpt-4o",
    "stream": true,
    "instructions": "You are a math tutor",
    "input": "Calculate the first 5 Fibonacci numbers",
    "tools": [{"type": "code_interpreter", "container": {"type": "auto"}}]
  }' 2>/dev/null | head -200