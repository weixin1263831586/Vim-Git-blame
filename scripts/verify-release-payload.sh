#!/usr/bin/env bash
# Verify the installer's default download path: resolve the main tip via the
# GitHub API, download vimb at that immutable commit, and check it is runnable.

set -euo pipefail

REPO="weixin1263831586/Vim-Git-blame"
API_TIP="https://api.github.com/repos/$REPO/commits/main"
RAW_BASE="https://raw.githubusercontent.com/$REPO"

API_JSON=$(mktemp "${TMPDIR:-/tmp}/vimb-release-api.XXXXXX")
PAYLOAD=$(mktemp "${TMPDIR:-/tmp}/vimb-release-payload.XXXXXX")
trap 'rm -f -- "$API_JSON" "$PAYLOAD"' EXIT

curl --proto '=https' --tlsv1.2 -fsSL "$API_TIP" -o "$API_JSON"
REF=$(sed -n 's/.*"sha": *"\([0-9a-f]\{40\}\)".*/\1/p' "$API_JSON" | head -n 1)
[ -n "$REF" ] || {
    printf 'release-payload: cannot resolve main tip sha\n' >&2
    exit 1
}

URL="$RAW_BASE/$REF/vimb"
curl --proto '=https' --tlsv1.2 -fsSL "$URL" -o "$PAYLOAD"
head -1 "$PAYLOAD" | grep -q '^#!/usr/bin/env bash' || {
    printf 'release-payload: payload is not the vimb script\n' >&2
    exit 1
}
VERSION=$(bash "$PAYLOAD" --version 2>/dev/null) || {
    printf 'release-payload: payload does not run\n' >&2
    exit 1
}
case "$VERSION" in
    'vimb '[0-9]*) ;;
    *) printf 'release-payload: unexpected version output: %s\n' "$VERSION" >&2
       exit 1 ;;
esac

printf 'PASS release payload %s @ %s\n' "$VERSION" "$REF"
