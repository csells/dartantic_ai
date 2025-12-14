#!/bin/bash
# SC-016: CLI -a flag overrides prompt file model
mkdir -p tmp
cat > tmp/cli_override.prompt << 'EOF'
---
model: anthropic
---
What is 9 + 6? Reply with just the number.
EOF

echo "CLI -a overrides prompt file model:"
echo '$ dartantic -a google -p @tmp/cli_override.prompt'
dart run bin/dartantic.dart -a google -p @tmp/cli_override.prompt
