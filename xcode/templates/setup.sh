#!/usr/bin/env sh

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

for dir in "$SCRIPT_DIR"/*
do
    if [[ -d "$dir" ]]; then
        ( cd "$dir" && ./setup.sh )
    fi
done

echo "==> Completed!"
