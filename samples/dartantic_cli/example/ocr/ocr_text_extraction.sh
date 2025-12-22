#!/bin/bash
# OCR (Optical Character Recognition) Example for Dartantic CLI
# Demonstrates Google Gemini's vision capability for text extraction from images

IMAGE_FILE="../../packages/dartantic_ai/example/bin/files/why-dartantic.png"

echo "=== Google OCR (Text Extraction) Example ==="
echo
echo "Extracting text from image: $IMAGE_FILE"
echo

dart run bin/dartantic.dart -a google chat \
  -p "Extract all text from this image. Preserve the formatting and structure: @$IMAGE_FILE"
