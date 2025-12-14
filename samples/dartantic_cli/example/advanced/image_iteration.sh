#!/bin/bash
# Iterative image generation: B&W to color
# 1. Generate a B&W robot image
# 2. Describe it using chat
# 3. Generate a colorized version

OUTPUT_DIR="tmp"
BW_IMAGE="$OUTPUT_DIR/robot_bw.png"
COLOR_IMAGE="$OUTPUT_DIR/robot_color.png"

echo "=== Iterative Image Generation ==="
echo

# Step 1: Generate B&W robot
echo "Step 1: Generate B&W robot image"
echo '$ dartantic generate -a google --mime image/png -p "Create robot_bw.png..."'
dart run bin/dartantic.dart generate -a google --mime image/png -o "$OUTPUT_DIR" \
    -p "Create a file named robot_bw.png containing a simple robot character in black and white line art only. No colors, no shading, just clean black lines on white background."

# Rename to expected name if it got a different name
LATEST=$(ls -t "$OUTPUT_DIR"/*.png 2>/dev/null | head -1)
if [ -n "$LATEST" ] && [ "$LATEST" != "$BW_IMAGE" ]; then
    mv "$LATEST" "$BW_IMAGE"
fi

if [ ! -f "$BW_IMAGE" ]; then
    echo "Error: No B&W image generated"
    exit 1
fi
echo "Generated: $BW_IMAGE"
echo

# Step 2: Describe the B&W image
echo "Step 2: Describe the robot"
echo "$ dartantic -p \"Describe this robot briefly: @$BW_IMAGE\""
DESCRIPTION=$(dart run bin/dartantic.dart -p "Describe this robot illustration in 2-3 sentences. Focus on its key features and design. @$BW_IMAGE")
echo "$DESCRIPTION"
echo

# Step 3: Generate colorized version
echo "Step 3: Generate colorized version"
echo '$ dartantic generate --mime image/png -p "Create robot_color.png..."'
dart run bin/dartantic.dart generate -a google --mime image/png -o "$OUTPUT_DIR" \
    -p "Create a file named robot_color.png with a colorful robot illustration based on this description: $DESCRIPTION. Use vibrant colors: electric blue body, orange accents, green glowing eyes. Keep the same design but make it colorful."

# Rename to expected name if it got a different name
LATEST=$(ls -t "$OUTPUT_DIR"/*.png 2>/dev/null | head -1)
if [ -n "$LATEST" ] && [ "$LATEST" != "$COLOR_IMAGE" ] && [ "$LATEST" != "$BW_IMAGE" ]; then
    mv "$LATEST" "$COLOR_IMAGE"
fi

if [ ! -f "$COLOR_IMAGE" ]; then
    echo "Error: No color image generated"
    exit 1
fi
echo "Generated: $COLOR_IMAGE"
echo

echo "=== Done! ==="
echo "B&W:   $BW_IMAGE"
echo "Color: $COLOR_IMAGE"
