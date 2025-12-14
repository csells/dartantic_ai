#!/bin/bash
# SC-015: Prompt file model overrides settings default
mkdir -p tmp
cat > tmp/settings_default.yaml << 'EOF'
default_agent: google
EOF

cat > tmp/override.prompt << 'EOF'
---
model: anthropic
---
What is 7 + 8? Reply with just the number.
EOF

echo "Prompt file model overrides settings:"
echo '$ dartantic -s tmp/settings_default.yaml -p @tmp/override.prompt'
dart run bin/dartantic.dart -s tmp/settings_default.yaml -p @tmp/override.prompt
