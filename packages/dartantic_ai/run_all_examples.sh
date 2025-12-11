#!/bin/bash

# Function to run an example
run_example() {
  local file=$1
  echo "----------------------------------------------------------------"
  echo "Running $file..."
  dart run "$file" > "output_${file##*/}.txt" 2>&1
  if [ $? -eq 0 ]; then
    echo "✅ PASS: $file"
  else
    echo "❌ FAIL: $file"
    echo "Output tail:"
    tail -n 5 "output_${file##*/}.txt"
  fi
}

# Check for API keys
HAS_GEMINI=false
if [ -n "$GEMINI_API_KEY" ]; then HAS_GEMINI=true; fi

HAS_ANTHROPIC=false
if [ -n "$ANTHROPIC_API_KEY" ]; then HAS_ANTHROPIC=true; fi

HAS_OPENAI=false
if [ -n "$OPENAI_API_KEY" ]; then HAS_OPENAI=true; fi

echo "API Keys: Gemini=$HAS_GEMINI, Anthropic=$HAS_ANTHROPIC, OpenAI=$HAS_OPENAI"

# List of examples
EXAMPLES=(
  "example/bin/chat.dart"
  "example/bin/custom_http_client.dart"
  "example/bin/custom_provider.dart"
  "example/bin/dotprompt.dart"
  "example/bin/embeddings.dart"
  "example/bin/logging.dart"
  "example/bin/mcp_servers.dart"
  "example/bin/media_gen.dart"
  "example/bin/model_string.dart"
  "example/bin/multi_provider.dart"
  "example/bin/multi_tool_call.dart"
  "example/bin/multi_turn_chat.dart"
  "example/bin/multimedia.dart"
  "example/bin/openai_compat.dart"
  "example/bin/provider_models.dart"
  "example/bin/single_tool_call.dart"
  "example/bin/single_turn_chat.dart"
  "example/bin/system_message.dart"
  "example/bin/thinking.dart"
  "example/bin/typed_output.dart"
  "example/bin/usage_tracking.dart"
)

# Anthropic Examples
ANTHROPIC_EXAMPLES=(
  "example/bin/server_side_tools_anthropic/server_side_code_interpreter.dart"
  "example/bin/server_side_tools_anthropic/server_side_web_fetch.dart"
  "example/bin/server_side_tools_anthropic/server_side_web_search.dart"
)

# OpenAI Examples
OPENAI_EXAMPLES=(
  "example/bin/server_side_tools_openai/server_side_code_interpreter.dart"
  "example/bin/server_side_tools_openai/server_side_image_gen.dart"
  "example/bin/server_side_tools_openai/server_side_vector_search.dart"
  "example/bin/server_side_tools_openai/server_side_web_search.dart"
)

# Run General Examples (Assume Gemini/General)
for ex in "${EXAMPLES[@]}"; do
  run_example "$ex"
done

# Run Anthropic Examples
if [ "$HAS_ANTHROPIC" = true ]; then
  for ex in "${ANTHROPIC_EXAMPLES[@]}"; do
    run_example "$ex"
  done
else
  echo "⚠️  Skipping Anthropic examples (missing ANTHROPIC_API_KEY)"
fi

# Run OpenAI Examples
if [ "$HAS_OPENAI" = true ]; then
  for ex in "${OPENAI_EXAMPLES[@]}"; do
    run_example "$ex"
  done
else
  echo "⚠️  Skipping OpenAI examples (missing OPENAI_API_KEY)"
fi
