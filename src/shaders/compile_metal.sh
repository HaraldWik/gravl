#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

# Prefer full Xcode if installed.
if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
elif [ -d "/Applications/Xcode-beta.app/Contents/Developer" ]; then
    DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
else
    DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
fi

export DEVELOPER_DIR

if ! xcrun --find metal >/dev/null 2>&1 ||
   ! xcrun --find metallib >/dev/null 2>&1; then
    echo "Error: Apple Metal shader tools are unavailable." >&2
    echo "Install Xcode and its Metal Toolchain, then rerun this script." >&2
    exit 1
fi

found=false

for file in *.metal; do
    [ -f "$file" ] || continue
    found=true

    air="${file%.metal}.air"
    output="${file%.metal}.metallib"

    echo "Compiling $file -> $output"

    if ! xcrun -sdk macosx metal -c "$file" -o "$air"; then
        echo "Failed to compile: $file" >&2
        exit 1
    fi

    if ! xcrun -sdk macosx metallib "$air" -o "$output"; then
        echo "Failed to link: $air" >&2
        exit 1
    fi

    rm -f "$air"
    echo "Successfully compiled: $output"
done

if [ "$found" = false ]; then
    echo "No .metal files found."
    exit 1
fi

echo "All shaders compiled successfully."