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
        # VIMB_INSTALL_TEST_SHA 为空时模拟 API 不可用（空响应）。
        # 真实 /commits/<ref> 响应除顶层 sha 外还带 tree/parents/files 的
        # sha 字段，ref 解析必须只取第一个。
        if [ -n "${VIMB_INSTALL_TEST_SHA:-}" ]; then
            printf '{"sha":"%s",\n "commit":{"tree":{"sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}},\n "parents":[{"sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}],\n "files":[{"sha":"cccccccccccccccccccccccccccccccccccccccc"},{"sha":"dddddddddddddddddddddddddddddddddddddddd"}]}\n' \
                "$VIMB_INSTALL_TEST_SHA"
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
        HOME="$WORK/home" \
        sh "$ROOT/install.sh"
}

run_installer_latest() {
    env PATH="$WORK/mock-bin:$PATH" \
        VIMB_INSTALL_TEST_SOURCE="$1" \
        BIN_DIR="$WORK/install-bin" \
        HOME="$WORK/home" \
        "${@:2}" \
        sh "$ROOT/install.sh"
}

mkdir -p "$WORK/home"
run_installer "$ROOT/vimb" >/dev/null
cmp -s "$ROOT/vimb" "$WORK/install-bin/vimb"
[ -x "$WORK/install-bin/vimb" ]
[ "$("$WORK/install-bin/vimb" --version)" = "vimb ${LOCAL_VERSION#v}" ]

# shell 别名：自动写入 bashrc；重复安装幂等；换 BIN_DIR 重装自动更新托管块
[ "$(grep -c 'vimb-installer:begin' "$WORK/home/.bashrc")" -eq 1 ]
grep -q "alias vimb='$WORK/install-bin/vimb'" "$WORK/home/.bashrc"
run_installer "$ROOT/vimb" >/dev/null
[ "$(grep -c 'vimb-installer:begin' "$WORK/home/.bashrc")" -eq 1 ]
grep -q "alias vimb='$WORK/install-bin/vimb'" "$WORK/home/.bashrc"
env PATH="$WORK/mock-bin:$PATH" \
    VIMB_INSTALL_TEST_SOURCE="$ROOT/vimb" \
    VIMB_VERSION="$LOCAL_VERSION" \
    VIMB_REF=local-test \
    VIMB_SHA256="$LOCAL_SHA256" \
    BIN_DIR="$WORK/install-bin2" \
    HOME="$WORK/home" \
    sh "$ROOT/install.sh" >/dev/null
[ "$(grep -c 'vimb-installer:begin' "$WORK/home/.bashrc")" -eq 1 ]
grep -q "alias vimb='$WORK/install-bin2/vimb'" "$WORK/home/.bashrc"
if grep -q "alias vimb='$WORK/install-bin/vimb'" "$WORK/home/.bashrc"; then
    printf 'FAIL installer left stale alias for old BIN_DIR\n' >&2
    exit 1
fi

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
        sh "$ROOT/install.sh" >/dev/null 2>&1; then
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
# 多 sha 的 API 响应不得泄漏到 ref：输出里不允许出现整行为 40 位 hex 的行
if grep -q '^[0-9a-f]\{40\}$' "$WORK/latest.out"; then
    printf 'FAIL installer resolved multiple shas from API response\n' >&2
    exit 1
fi

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
