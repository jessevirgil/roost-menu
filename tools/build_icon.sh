#!/bin/zsh
# Regenerates RoostMenu/Assets.xcassets/AppIcon.appiconset from tools/make_icon.swift
set -e
cd "$(dirname "$0")/.."
SET=RoostMenu/Assets.xcassets/AppIcon.appiconset
mkdir -p "$SET"
qlmanage -t -s 2248 -o tools tools/roost-icon.svg >/dev/null 2>&1 && mv tools/roost-icon.svg.png tools/roost-icon.png
swift tools/make_icon.swift "$SET/icon_1024.png" tools/roost-icon.png >/dev/null
for n in 16 32 64 128 256 512; do sips -z $n $n "$SET/icon_1024.png" --out "$SET/icon_$n.png" >/dev/null; done
cat > RoostMenu/Assets.xcassets/Contents.json <<'J'
{ "info" : { "author" : "xcode", "version" : 1 } }
J
cat > "$SET/Contents.json" <<'J'
{
  "images" : [
    { "filename" : "icon_16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png",  "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
J
echo "icon set written to $SET"
