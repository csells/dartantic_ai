#!/bin/bash
# Run all dartantic CLI examples
set -e

echo "=== Dartantic CLI Examples ==="
echo

for dir in basic attachments templates structured_output advanced generate embed server_tools environment; do
    if [ -d "example/$dir" ]; then
        echo "=== $(echo "$dir" | tr '[:lower:]' '[:upper:]') ==="
        for script in "example/$dir"/*.sh; do
            if [ -f "$script" ]; then
                echo "--- $(basename "$script" .sh) ---"
                bash "$script"
                echo
            fi
        done
        echo
    fi
done

echo "=== All examples complete! ==="
