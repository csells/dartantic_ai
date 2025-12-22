#!/bin/bash
# Iterative image generation: B&W to color using native image editing
# 1. Generate a B&W robot image
# 2. Colorize it using native image editing (pass original as attachment)

OUTPUT_DIR="tmp"
BW_IMAGE="$OUTPUT_DIR/robot_bw.png"
COLOR_IMAGE="$OUTPUT_DIR/robot_color.png"

echo "=== Iterative Image Generation (Native Image Editing) ==="
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

# Step 2: Colorize using native image editing (Google Imagen)
# This uses the @filename syntax to attach the B&W image,
# triggering native image editing instead of generating from scratch
echo "Step 2: Colorize using native image editing"
echo '$ dartantic generate -a google --mime image/png -p "Colorize this image... @robot_bw.png"'
dart run bin/dartantic.dart generate -a google --mime image/png -o "$OUTPUT_DIR" \
    -p "Colorize this black and white robot drawing. Make the robot body electric blue, the eyes bright green, and add orange accents. Keep all the original black lines. @$BW_IMAGE"

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
echo
echo "Note: This example uses Google's native Imagen image editing."
echo "The colorized version is created by editing the original B&W image,"
echo "not by generating a new image from scratch."
