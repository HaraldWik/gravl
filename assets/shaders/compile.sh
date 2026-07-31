#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")" || exit 1

for file in *.vert *.frag; do
    [ -e "$file" ] || continue

    case "$file" in
        *.vert)
            stage="vert"
            ;;
        *.frag)
            stage="frag"
            ;;
        *)
            echo "Skipping unknown file: $file"
            continue
            ;;
    esac

    output="$file.spv"

    echo "Compiling $file -> $output"

    if ! glslc "$file" \
        -fshader-stage="$stage" \
        -o "$output"
    then
        echo "Failed to compile: $file" >&2
        exit 1
    fi

    echo "Successfully compiled: $output"
done

echo "All shaders compiled successfully."