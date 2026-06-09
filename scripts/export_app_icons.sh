#!/bin/bash
# Export app icons from SVG to PNG at required sizes

SVG_SOURCE="docs/icon_source_v2.svg"
OUTPUT_DIR="Upmarket/Upmarket/Assets.xcassets/AppIcon.appiconset"
SIZES=(16 32 64 128 256 512 1024)

if [ ! -f "$SVG_SOURCE" ]; then
    echo "Error: $SVG_SOURCE not found"
    exit 1
fi

# Convert SVG to PDF first (using system capabilities), then PDF to PNG
# macOS has built-in PDF rendering via sips

for size in "${SIZES[@]}"; do
    output_file="$OUTPUT_DIR/icon_${size}.png"

    # Use sips to convert - requires intermediate PDF or direct rasterization
    # For SVG, we'll use a PDF intermediate on macOS

    echo "Generating icon_${size}.png..."

    # Create a temporary PDF from SVG by rendering it
    # This uses macOS's built-in PDF rendering capabilities
    temp_pdf="/tmp/temp_icon_${size}.pdf"

    # Use Quartz PDF tools or create via intermediate step
    # For now, try direct conversion if possible

    if command -v rsvg-convert &> /dev/null; then
        rsvg-convert -w "$size" -h "$size" "$SVG_SOURCE" -o "$output_file"
    elif command -v inkscape &> /dev/null; then
        inkscape -w "$size" -h "$size" "$SVG_SOURCE" -o "$output_file"
    else
        echo "Warning: No SVG converter found. Please install rsvg-convert or inkscape"
        echo "  brew install librsvg  # or"
        echo "  brew install inkscape"
        exit 1
    fi
done

echo "Icons exported successfully to $OUTPUT_DIR"
