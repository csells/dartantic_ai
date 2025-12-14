#!/bin/bash
# SC-019: Agent with output_schema in settings
OUTPUT_DIR="tmp"
SETTINGS_FILE="$OUTPUT_DIR/extractor_settings.yaml"
mkdir -p "$OUTPUT_DIR"

# Create settings with extractor agent
cat > "$SETTINGS_FILE" << 'EOF'
agents:
  extractor:
    model: openai:gpt-4o-mini
    system: Extract entities from text.
    output_schema:
      type: object
      properties:
        entities:
          type: array
          items:
            type: object
            properties:
              name:
                type: string
              type:
                type: string
      required:
        - entities
EOF

echo "Using agent with output_schema from settings:"
echo '$ dartantic -s settings.yaml -a extractor -p "John works at Acme Corp."'
dart run bin/dartantic.dart -s "$SETTINGS_FILE" -a extractor -p "John Smith works at Acme Corp as a software engineer."
