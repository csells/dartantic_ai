#!/bin/bash
# Run all dartantic CLI examples
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "=== Dartantic CLI Examples ==="
echo

for dir in basic attachments templates structured_output advanced; do
    if [ -d "example/$dir" ]; then
        echo "=== ${dir^^} ==="
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
