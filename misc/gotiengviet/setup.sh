#!/bin/sh

echo ""
echo "Change GoTiengViet menu bar icons"

CURRENT_DIR="$(cd "$(dirname "$0")"; pwd)";
for icon in {E,E@2x,V,V@2x}; do
    cp -f "${CURRENT_DIR}/Resources/${icon}.png" "/Applications/GoTiengViet.app/Contents/Resources/${icon}.png"
done