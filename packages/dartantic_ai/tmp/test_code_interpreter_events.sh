#!/bin/bash

echo "Testing Code Interpreter to capture all event types..."
echo ""

OPENAI_API_KEY=$(grep OPENAI_API_KEY ~/global_env.sh | cut -d'"' -f2)

# Test with simpler prompt to actually trigger code execution
curl -X POST https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Accept: text/event-stream" \
  -N \
  -d '{
    "model": "gpt-4o",
    "stream": true,
    "instructions": "You must use Python code to answer",
    "input": "What is 2+2? Use code.",
    "tools": [{"type": "code_interpreter", "container": {"type": "auto"}}]
  }' 2>/dev/null | grep -E "event:|container_id|code_interpreter" | head -100