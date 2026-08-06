#!/bin/bash
# Regenerates AppIcon.appiconset from a single square source image (1024x1024 or larger).
# This is how you "switch" the app icon: point this script at a different PNG and rebuild.
#
# Usage: ./Scripts/make-appicon.sh [path/to/source.png]
#        (defaults to Design/AppIcon/uttr-icon-source.png)
set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE="${1:-Design/AppIcon/uttr-icon-source.png}"
ICONSET_DIR="Uttr/Resources/Assets.xcassets/AppIcon.appiconset"

if [[ ! -f "$SOURCE" ]]; then
    echo "error: source image not found: $SOURCE" >&2
    exit 1
fi

# size:scale pairs required by the macOS appiconset
SPECS=(
    "16 1" "16 2"
    "32 1" "32 2"
    "128 1" "128 2"
    "256 1" "256 2"
    "512 1" "512 2"
)

echo "Generating icons from $SOURCE ..."
rm -f "$ICONSET_DIR"/*.png

IMAGES_JSON=""
for spec in "${SPECS[@]}"; do
    read -r size scale <<< "$spec"
    px=$(( size * scale ))
    if [[ $scale -eq 1 ]]; then
        fname="icon_${size}x${size}.png"
    else
        fname="icon_${size}x${size}@${scale}x.png"
    fi
    sips -z "$px" "$px" "$SOURCE" --out "$ICONSET_DIR/$fname" >/dev/null
    IMAGES_JSON+="    {
      \"filename\" : \"$fname\",
      \"idiom\" : \"mac\",
      \"scale\" : \"${scale}x\",
      \"size\" : \"${size}x${size}\"
    },
"
done
IMAGES_JSON="${IMAGES_JSON%,$'\n'}"

cat > "$ICONSET_DIR/Contents.json" <<EOF
{
  "images" : [
$IMAGES_JSON
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "Done. $(ls "$ICONSET_DIR" | grep -c '\.png$') PNGs written to $ICONSET_DIR"
echo "Rebuild the app for the new icon to take effect."
