#!/bin/bash
# SC-031: Agent with system prompt
OUTPUT_DIR="tmp"
SETTINGS_FILE="$OUTPUT_DIR/pirate_settings.yaml"
mkdir -p "$OUTPUT_DIR"

# Create settings with pirate agent
cat > "$SETTINGS_FILE" << 'EOF'
agents:
  pirate:
    model: google
    system: You are a pirate. Always respond with "Arrr!" at the start of your response.
EOF

echo "Using agent with custom system prompt:"
echo '$ dartantic -s settings.yaml -a pirate -p "What is your favorite food?"'
dart run bin/dartantic.dart -s "$SETTINGS_FILE" -a pirate -p "What is your favorite food?"
