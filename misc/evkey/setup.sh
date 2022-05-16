#!/bin/sh

[ "$(uname -s)" != "Darwin" ] && exit 0

echo ""
echo "Change EVKey menu bar icons"

CURRENT_DIR="$(cd "$(dirname "$0")"; pwd)";
for icon in {en,en_l,vn,vn_l}; do
    cp -f "${CURRENT_DIR}/Resources/${icon}.tiff" "/Applications/EVKey.app/Contents/Resources/${icon}.tiff"
done
