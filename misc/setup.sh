#!/bin/sh

# Setup macOS defaults

CURRENT_DIR="$(cd "$(dirname "$0")"; pwd)";

execute() {
    chmod +x "$1"; "$1";
}

for file in $CURRENT_DIR/*/setup.sh; do
    echo "Setup file: " "$file"
	[ -r "$file" ] && [ -f "$file" ] && execute "$file"
done;
unset file;
unset execute;
