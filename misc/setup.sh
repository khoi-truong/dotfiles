#!/bin/sh

# Setup macOS defaults
execute() {
    chmod +x "$1"; "$1";
}

for file in ./*/setup.sh; do
	[ -r "$file" ] && [ -f "$file" ] && execute "$file"
done;
unset file;
unset execute;
