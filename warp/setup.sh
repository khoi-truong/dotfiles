#!/bin/sh

echo ""
echo "Copy Warp custom themes"

CURRENT_DIR="$(cd "$(dirname "$0")"; pwd)";

mkdir -p ~/.warp/themes
cp -R ${CURRENT_DIR}/themes/* ~/.warp/themes
