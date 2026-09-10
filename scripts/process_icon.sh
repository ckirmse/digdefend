#!/usr/bin/env bash
# Turns a Studio window capture with a chroma-green backdrop into a 512x512
# transparent icon PNG (icon capture pipeline, see docs/icon-capture.md).
# Usage: scripts/process_icon.sh <studio_capture.png> <out_final.png>
set -euo pipefail

INPUT="$1"
OUTPUT="$2"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

GREEN='#00ff00'

# viewport = bounding box of green pixels
magick "$INPUT" -fuzz 18% -fill black +opaque "$GREEN" -fill white -opaque "$GREEN" \
	-colorspace gray -threshold 50% "$WORK/mask.png"
BBOX="$(magick "$WORK/mask.png" -trim -format "%wx%h+%X+%Y" info:)"
magick "$INPUT" -crop "$BBOX" +repage "$WORK/viewport.png"
WIDTH="$(magick identify -format %w "$WORK/viewport.png")"

# paint out the view-selector cube corner (top-right, cannot be disabled by
# API), then chroma-key the backdrop
magick "$WORK/viewport.png" -fill "$GREEN" -draw "rectangle $((WIDTH - 230)),0 $WIDTH,270" \
	-fuzz 12% -transparent "$GREEN" "$WORK/keyed.png"

# keep only large opaque components; stray gizmo/handle lines survive keying otherwise
magick "$WORK/keyed.png" \( +clone -alpha extract \
	-define connected-components:area-threshold=30000 \
	-define connected-components:mean-color=true -connected-components 8 -threshold 50% \) \
	-compose CopyOpacity -composite "$WORK/clean.png"
magick "$WORK/clean.png" -trim +repage "$WORK/trimmed.png"

# square 512 canvas with ~5% margin, plus green despill on the edges
magick "$WORK/trimmed.png" -resize 464x464 -background none -gravity center -extent 512x512 \
	-channel G -fx "g>(r>b?r:b)?(r>b?r:b):g" +channel "$OUTPUT"

echo "wrote $OUTPUT"
