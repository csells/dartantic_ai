#!/bin/bash
# SC-028: Agent with server_tools disabled in settings
mkdir -p tmp
cat > tmp/no_tools_settings.yaml << 'EOF'
agents:
  simple:
    model: google
    server_tools: false
EOF

echo "Agent with server tools disabled:"
echo '$ dartantic -s tmp/no_tools_settings.yaml -a simple -p "Hello"'
dart run bin/dartantic.dart -s tmp/no_tools_settings.yaml -a simple -p "Hello"
