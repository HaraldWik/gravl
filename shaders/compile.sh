#!/bin/bash

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
    esac

    glslc "$file" -fshader-stage="$stage" -o "$file.spv"
done