#!/usr/bin/env bash
# Verify that install.sh's immutable default payload still exists and matches.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
INSTALLER="$ROOT/install.sh"

read_default() {
    local name=$1 value
    value=$(sed -n "s/^${name}=\"\([^\"]*\)\"$/\1/p" "$INSTALLER")
    [ -n "$value" ] || {
        printf 'release-payload: cannot read %s from install.sh\n' "$name" >&2
        exit 1
    }
    printf '%s\n' "$value"
}

VERSION=$(read_default DEFAULT_VERSION)
REF=$(read_default DEFAULT_REF)
EXPECTED_SHA256=$(read_default DEFAULT_SHA256)
URL="https://raw.githubusercontent.com/weixin1263831586/Vim-Git-blame/$REF/vimb"
PAYLOAD=$(mktemp "${TMPDIR:-/tmp}/vimb-release-payload.XXXXXX")
trap 'rm -f -- "$PAYLOAD"' EXIT

curl --proto '=https' --tlsv1.2 -fsSL "$URL" -o "$PAYLOAD"
ACTUAL_SHA256=$(sha256sum "$PAYLOAD" | awk '{print $1}')
[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || {
    printf 'release-payload: SHA mismatch for %s\n' "$URL" >&2
    printf 'expected %s\nactual   %s\n' "$EXPECTED_SHA256" "$ACTUAL_SHA256" >&2
    exit 1
}
[ "$(bash "$PAYLOAD" --version)" = "vimb ${VERSION#v}" ] || {
    printf 'release-payload: version mismatch for %s\n' "$URL" >&2
    exit 1
}

printf 'PASS release payload %s @ %s\n' "$VERSION" "$REF"
