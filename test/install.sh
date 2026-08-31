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
case "$*" in
    *api.github.com*)
        # VIMB_INSTALL_TEST_SHA 为空时模拟 API 不可用（空响应）
        if [ -n "${VIMB_INSTALL_TEST_SHA:-}" ]; then
            printf '{"sha":"%s"}\n' "$VIMB_INSTALL_TEST_SHA"
        fi
        exit 0
        ;;
esac
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

run_installer_latest() {
    env PATH="$WORK/mock-bin:$PATH" \
        VIMB_INSTALL_TEST_SOURCE="$1" \
        BIN_DIR="$WORK/install-bin" \
        "${@:2}" \
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

# 默认（自动取最新）模式：API 解析出不可变 ref 后正常安装
rm -f "$WORK/install-bin/vimb"
run_installer_latest "$ROOT/vimb" \
    VIMB_INSTALL_TEST_SHA=1111111111111111111111111111111111111111 \
    >"$WORK/latest.out" 2>&1
cmp -s "$ROOT/vimb" "$WORK/install-bin/vimb"
[ -x "$WORK/install-bin/vimb" ]
grep -q 'ref=1111111111111111111111111111111111111111' "$WORK/latest.out"

# 默认模式：API 不可用时回退到 main 引用，仍能安装
rm -f "$WORK/install-bin/vimb"
run_installer_latest "$ROOT/vimb" >"$WORK/fallback.out" 2>&1
cmp -s "$ROOT/vimb" "$WORK/install-bin/vimb"
grep -q '回退到可变引用 main' "$WORK/fallback.out"

# 默认模式：非 vimb 内容（如错误页面）必须被拒绝
printf '<html>error page</html>\n' >"$WORK/not-vimb"
if run_installer_latest "$WORK/not-vimb" \
        VIMB_INSTALL_TEST_SHA=1111111111111111111111111111111111111111 \
        >/dev/null 2>&1; then
    printf 'FAIL installer accepted a non-vimb payload\n' >&2
    exit 1
fi

printf 'PASS installer\n'
