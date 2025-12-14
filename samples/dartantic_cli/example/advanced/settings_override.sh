#!/bin/bash
# SC-033: Settings file override path
mkdir -p tmp
cat > tmp/custom_settings.yaml << 'EOF'
default_agent: custom
agents:
  custom:
    model: google
    system: Always respond with exactly one word.
EOF

echo "Using custom settings file:"
echo '$ dartantic -s tmp/custom_settings.yaml -p "How are you?"'
dart run bin/dartantic.dart -s tmp/custom_settings.yaml -p "How are you?"
