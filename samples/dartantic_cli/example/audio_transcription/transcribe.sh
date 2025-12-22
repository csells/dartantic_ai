#!/bin/bash
# Audio Transcription Examples for Dartantic CLI
# Demonstrates Google's native audio transcription capability

AUDIO_FILE="../../packages/dartantic_ai/example/bin/files/welcome-to-dartantic.mp3"

echo "=== Google Audio Transcription Examples ==="
echo

# Example 1: Plain text transcription
echo "1. Plain Text Transcription:"
dart run bin/dartantic.dart -a google chat \
  -p "Transcribe this audio file word for word: @$AUDIO_FILE"

echo
echo

# Example 2: JSON transcription with timestamps
echo "2. JSON Transcription with Word-Level Timestamps:"
dart run bin/dartantic.dart -a google chat \
  --output-schema '{
    "type": "object",
    "properties": {
      "transcript": {"type": "string"},
      "words": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "word": {"type": "string"},
            "start_time": {"type": "number"},
            "end_time": {"type": "number"}
          }
        }
      }
    }
  }' \
  -p "Transcribe this audio file with word-level timestamps (in seconds): @$AUDIO_FILE"
