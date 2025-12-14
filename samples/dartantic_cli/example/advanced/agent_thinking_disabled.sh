#!/bin/bash
# SC-024: Agent with thinking disabled in settings
mkdir -p tmp
cat > tmp/quick_settings.yaml << 'EOF'
agents:
  quick:
    model: google:gemini-2.5-flash
    system: Be concise.
    thinking: false
EOF

echo "Agent with thinking disabled:"
echo '$ dartantic -s tmp/quick_settings.yaml -a quick -p "Hello"'
dart run bin/dartantic.dart -s tmp/quick_settings.yaml -a quick -p "Hello"
