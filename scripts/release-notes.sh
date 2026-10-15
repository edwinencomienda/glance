#!/usr/bin/env bash
# Prints the release notes for a version: its section in CHANGELOG.md.
# Usage: scripts/release-notes.sh 1.1.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release-notes.sh X.Y.Z}"
awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { found = 1; next }
  found && /^## \[/ { exit }
  found && /^\[.*\]: / { exit }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d'
