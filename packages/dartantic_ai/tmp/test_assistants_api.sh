#!/bin/bash

echo "Testing Assistants API with code_interpreter..."
echo ""

OPENAI_API_KEY=$(grep OPENAI_API_KEY ~/global_env.sh | cut -d'"' -f2)

# Create an assistant with code_interpreter
curl -X POST https://api.openai.com/v1/assistants \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "OpenAI-Beta: assistants=v2" \
  -d '{
    "model": "gpt-4o",
    "name": "Code Test Assistant",
    "tools": [
      {
        "type": "code_interpreter"
      }
    ]
  }' | python3 -m json.tool