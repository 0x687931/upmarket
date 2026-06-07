#!/bin/sh

set -eu

metadata_path="${1:?metadata output path required}"

commit="unknown"
full_commit="unknown"
dirty="false"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    commit="$(git rev-parse --short=7 HEAD 2>/dev/null || printf unknown)"
    full_commit="$(git rev-parse HEAD 2>/dev/null || printf unknown)"
    if [ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null || true)" ]; then
        dirty="true"
    fi
fi

mkdir -p "$(dirname "$metadata_path")"

{
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0">'
    printf '%s\n' '<dict>'
    printf '%s\n' '    <key>GitCommit</key>'
    printf '    <string>%s</string>\n' "$commit"
    printf '%s\n' '    <key>GitFullCommit</key>'
    printf '    <string>%s</string>\n' "$full_commit"
    printf '%s\n' '    <key>GitDirty</key>'
    if [ "$dirty" = "true" ]; then
        printf '%s\n' '    <true/>'
    else
        printf '%s\n' '    <false/>'
    fi
    printf '%s\n' '</dict>'
    printf '%s\n' '</plist>'
} > "$metadata_path"
