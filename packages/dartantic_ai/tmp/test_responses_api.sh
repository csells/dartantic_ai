#!/bin/bash

echo "Testing actual Responses API (/v1/responses) with code_interpreter..."
echo ""

OPENAI_API_KEY=$(grep OPENAI_API_KEY ~/global_env.sh | cut -d'"' -f2)

# Test the actual Responses API endpoint with code_interpreter
curl -X POST https://api.openai.com/v1/responses \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -d '{
    "model": "gpt-4o",
    "tools": [
      {
        "type": "code_interpreter",
        "container": {"type": "auto"}
      }
    ],
    "instructions": "You are a personal math tutor. When asked a math question, write and run code using the python tool to answer the question.",
    "input": "I need to solve the equation 3x + 11 = 14. Can you help me?"
  }'