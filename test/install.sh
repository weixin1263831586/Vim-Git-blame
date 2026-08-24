#!/usr/bin/env bash
# Installer regression: pinning, checksum enforcement, version, and mode.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/vimb-install-test.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/mock-bin" "$WORK/install-bin"
LOCAL_VERSION="v$("$ROOT/vimb" --version | sed 's/^vimb //')"
LOCAL_SHA256=$(sha256sum "$ROOT/vimb" | awk '{print $1}')

cat >"$WORK/mock-bin/curl" <<'EOF'
#!/usr/bin/env bash
set -eu
exec /bin/cat "$VIMB_INSTALL_TEST_SOURCE"
EOF
chmod 755 "$WORK/mock-bin/curl"

run_installer() {
    env PATH="$WORK/mock-bin:$PATH" \
        VIMB_INSTALL_TEST_SOURCE="$1" \
        VIMB_VERSION="$LOCAL_VERSION" \
        VIMB_REF=local-test \
        VIMB_SHA256="$LOCAL_SHA256" \
        BIN_DIR="$WORK/install-bin" \
        bash "$ROOT/install.sh"
}

run_installer "$ROOT/vimb" >/dev/null
cmp -s "$ROOT/vimb" "$WORK/install-bin/vimb"
[ -x "$WORK/install-bin/vimb" ]
[ "$("$WORK/install-bin/vimb" --version)" = "vimb ${LOCAL_VERSION#v}" ]

cp "$ROOT/vimb" "$WORK/tampered-vimb"
printf '\n# tampered\n' >>"$WORK/tampered-vimb"
if run_installer "$WORK/tampered-vimb" >/dev/null 2>&1; then
    printf 'FAIL installer accepted a checksum mismatch\n' >&2
    exit 1
fi

if env PATH="$WORK/mock-bin:$PATH" \
        VIMB_INSTALL_TEST_SOURCE="$ROOT/vimb" \
        VIMB_VERSION=v9.9.9 \
        VIMB_REF=test-ref \
        BIN_DIR="$WORK/install-bin" \
        bash "$ROOT/install.sh" >/dev/null 2>&1; then
    printf 'FAIL installer accepted a custom version/ref without VIMB_SHA256\n' >&2
    exit 1
fi

printf 'PASS installer\n'
