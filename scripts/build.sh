#!/usr/bin/env bash
# Assemble the development sources into the single-file vimb distribution.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEMPLATE="$ROOT/src/launcher.sh"
CHECK_ONLY=0
if [ "${1:-}" = "--check" ]; then
    CHECK_ONLY=1
    OUTPUT="$ROOT/vimb"
elif [ "$#" -gt 1 ]; then
    printf 'usage: %s [--check|OUTPUT]\n' "$0" >&2
    exit 2
else
    OUTPUT=${1:-"$ROOT/vimb"}
fi
MARKER='# @VIMB_VIMSCRIPT@'
MODULES=(
    00_state.vim
    10_git.vim
    20_commit_cache.vim
    30_visual.vim
    40_ui.vim
    50_blame.vim
    60_stack.vim
    70_history.vim
    80_commit_panel.vim
    90_lifecycle.vim
    100_remote.vim
    110_bootstrap.vim
)

TMP_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/vimb-build.XXXXXX")
trap 'rm -f -- "$TMP_OUTPUT"' EXIT

marker_count=0
while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$MARKER" ]; then
        marker_count=$((marker_count + 1))
        for module in "${MODULES[@]}"; do
            module_path="$ROOT/src/vim/$module"
            [ -f "$module_path" ] || {
                printf 'vimb-build: missing module: %s\n' "$module_path" >&2
                exit 1
            }
            while IFS= read -r module_line || [ -n "$module_line" ]; do
                printf '%s\n' "$module_line"
            done <"$module_path"
        done
    else
        printf '%s\n' "$line"
    fi
done <"$TEMPLATE" >"$TMP_OUTPUT"

[ "$marker_count" -eq 1 ] || {
    printf 'vimb-build: expected exactly one marker, found %s\n' "$marker_count" >&2
    exit 1
}

chmod 755 "$TMP_OUTPUT"
if [ -f "$OUTPUT" ] && cmp -s "$TMP_OUTPUT" "$OUTPUT"; then
    exit 0
fi
if [ "$CHECK_ONLY" -eq 1 ]; then
    printf 'vimb-build: %s is stale; run scripts/build.sh\n' "$OUTPUT" >&2
    exit 1
fi
mv -- "$TMP_OUTPUT" "$OUTPUT"
trap - EXIT
