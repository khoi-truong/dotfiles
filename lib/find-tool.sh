#!/bin/sh
# find_tool <name>: print the path of <name> from PATH, or else from mise.
# Covers non-interactive shells (git hooks, cron) where mise is not activated.
# POSIX sh: this file is sourced by hooks and scripts alike.

find_tool() {
  command -v "$1" 2>/dev/null || mise which "$1" 2>/dev/null
}
