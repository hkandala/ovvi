#!/usr/bin/env bash
# Cuts the welcome's close-ups out of shoot.sh's shots (/tmp/p57y2-shots, 2x) into Ovvi/Onboarding/Welcome.xcassets:
# one image set per picture, light (Any) and dark, HEIC at 2x. Usage: scripts/welcome-pictures/crop.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
shots=/tmp/p57y2-shots
assets=$here/../../Ovvi/Onboarding/Welcome.xcassets/welcome
# name, shot, then x y width height in the shot's points (the main window's, 1200 x 760).
crops="
hero expiry 0 40 1200 480
tabs expiry 300 4 800 38
spaces expiry 6 82 286 375
chooser chooser 575 296 345 214
chat darkmode 304 330 420 320
browser expiry 750 200 300 210
git darkmode 752 255 300 210
files files 750 140 300 210
plugin plugin 750 48 420 300
menu menu 112 42 162 236
machines machines 236 152 460 150
"
rm -rf "$assets"
mkdir -p "$assets"
printf '{ "info": { "author": "xcode", "version": 1 }, "properties": { "provides-namespace": true } }\n' \
    >"$assets/Contents.json"
while read -r name shot x y width height; do
    [ -n "$name" ] || continue
    set="$assets/$name.imageset"
    mkdir -p "$set"
    for look in light dark; do
        [ -f "$shots/$shot-$look.png" ] || { echo "no $shots/$shot-$look.png" >&2 && exit 1; }
        sips -c $((height * 2)) $((width * 2)) --cropOffset $((y * 2)) $((x * 2)) "$shots/$shot-$look.png" \
            --out "$set/$name-$look.png" >/dev/null
        sips -s format heic -s formatOptions 90 "$set/$name-$look.png" --out "$set/$name-$look.heic" >/dev/null
        rm "$set/$name-$look.png"
    done
    cat >"$set/Contents.json" <<EOF
{
  "images": [
    { "filename": "$name-light.heic", "idiom": "universal", "scale": "2x" },
    { "appearances": [{ "appearance": "luminosity", "value": "dark" }], "filename": "$name-dark.heic",
      "idiom": "universal", "scale": "2x" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
EOF
done <<<"$crops"
du -sh "$assets"
