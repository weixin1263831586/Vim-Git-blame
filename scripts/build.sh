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
    state.vim
    git.vim
    commit_cache.vim
    visual.vim
    ui.vim
    blame.vim
    stack.vim
    history.vim
    commit_panel.vim
    lifecycle.vim
    remote.vim
    bootstrap.vim
)

# MODULES 是模块加载顺序的唯一来源。既拒绝重复项，也拒绝 src/vim 中
# 未登记的 .vim 文件，避免新增模块被构建过程静默遗漏。
for ((i = 0; i < ${#MODULES[@]}; i++)); do
    module_path="$ROOT/src/vim/${MODULES[i]}"
    [ -f "$module_path" ] || {
        printf 'vimb-build: missing module: %s\n' "$module_path" >&2
        exit 1
    }
    for ((j = i + 1; j < ${#MODULES[@]}; j++)); do
        [ "${MODULES[i]}" != "${MODULES[j]}" ] || {
            printf 'vimb-build: duplicate module: %s\n' "${MODULES[i]}" >&2
            exit 1
        }
    done
done
for module_path in "$ROOT/src/vim/"*.vim; do
    [ -e "$module_path" ] || continue
    module=${module_path##*/}
    declared=0
    for expected in "${MODULES[@]}"; do
        if [ "$module" = "$expected" ]; then
            declared=1
            break
        fi
    done
    [ "$declared" -eq 1 ] || {
        printf 'vimb-build: undeclared module: %s\n' "$module_path" >&2
        exit 1
    }
done

TMP_OUTPUT=$(mktemp "${TMPDIR:-/tmp}/vimb-build.XXXXXX")
trap 'rm -f -- "$TMP_OUTPUT"' EXIT

marker_count=0
while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$MARKER" ]; then
        marker_count=$((marker_count + 1))
        for module in "${MODULES[@]}"; do
            module_path="$ROOT/src/vim/$module"
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
