#!/usr/bin/env bash
# vimb 安装脚本：从 GitHub 下载最新 vimb 并安装到 ~/.local/bin
# 用法: curl --proto '=https' --tlsv1.2 -fsSL \
#       https://raw.githubusercontent.com/weixin1263831586/Vim-Git-blame/main/install.sh | sh
# 可通过 BIN_DIR 环境变量覆盖安装目录，例如: BIN_DIR=/usr/local/bin sh install.sh
# 默认安装 main 最新提交：先经 GitHub API 把 main 解析为不可变 commit 再下载。
# 需要固定内容时用 VIMB_REF=<commit> VIMB_SHA256=<该 vimb 的 SHA-256> 覆盖，
# 自定义 VIMB_REF 必须同时提供 VIMB_SHA256；VIMB_VERSION 可选，用于校验版本号。

set -eu

msg() { printf 'vimb-installer: %s\n' "$*"; }
die() { printf 'vimb-installer: %s\n' "$*" >&2; exit 1; }

REPO="weixin1263831586/Vim-Git-blame"
RAW_BASE="https://raw.githubusercontent.com/$REPO"
API_TIP="https://api.github.com/repos/$REPO/commits/main"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
    || die "需要 curl 或 wget 之一"
command -v vim >/dev/null 2>&1 || die "未找到 vim，请先安装 vim"
command -v git >/dev/null 2>&1 || die "未找到 git，请先安装 git"

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 -fsSL "$1"
    else
        wget -qO- "$1"
    fi
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        die "需要 sha256sum 或 shasum 校验下载内容"
    fi
}

REF="${VIMB_REF:-}"
EXPECTED_SHA256="${VIMB_SHA256:-}"
if [ -n "$REF" ] && [ -z "$EXPECTED_SHA256" ]; then
    die "自定义 VIMB_REF 时必须同时提供 VIMB_SHA256"
fi
if [ -n "$EXPECTED_SHA256" ]; then
    case "$EXPECTED_SHA256" in
        *[!0-9a-f]*|'') die "VIMB_SHA256 必须是小写十六进制 SHA-256" ;;
    esac
    [ "${#EXPECTED_SHA256}" -eq 64 ] || die "VIMB_SHA256 长度必须为 64"
fi

if [ -z "$REF" ]; then
    REF=''
    if API_JSON=$(fetch "$API_TIP" 2>/dev/null); then
        REF=$(printf '%s\n' "$API_JSON" \
            | sed -n 's/.*"sha": *"\([0-9a-f]\{40\}\)".*/\1/p' \
            | head -n 1)
    fi
    if [ -n "$REF" ]; then
        msg "main 最新提交: $REF"
    else
        REF=main
        msg "警告: 无法访问 GitHub API，回退到可变引用 main"
    fi
fi
URL="$RAW_BASE/$REF/vimb"

TMP_FILE=$(mktemp "${TMPDIR:-/tmp}/vimb-install.XXXXXX")
trap 'rm -f -- "$TMP_FILE"' EXIT

msg "正在从 $URL 下载 vimb ..."
fetch "$URL" >"$TMP_FILE"

if [ -n "$EXPECTED_SHA256" ]; then
    ACTUAL_SHA256=$(sha256_file "$TMP_FILE")
    [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] \
        || die "SHA-256 校验失败，拒绝安装（下载内容可能损坏或被篡改）"
fi

# 校验下载内容确实是 vimb 脚本，避免把错误页面装进 PATH
head -1 "$TMP_FILE" | grep -q '^#!/usr/bin/env bash' \
    || die "下载内容不是 vimb 脚本，请检查网络后重试"
grep -q '^VERSION=' "$TMP_FILE" \
    || die "下载内容不完整，请检查网络后重试"
GOT_VERSION=$(bash "$TMP_FILE" --version 2>/dev/null) \
    || die "下载脚本无法执行，请检查网络后重试"
if [ -n "${VIMB_VERSION:-}" ]; then
    [ "$GOT_VERSION" = "vimb ${VIMB_VERSION#v}" ] \
        || die "下载脚本版本与请求的 $VIMB_VERSION 不一致（实际 $GOT_VERSION）"
else
    case "$GOT_VERSION" in
        'vimb '[0-9]*) ;;
        *) die "下载脚本版本异常: $GOT_VERSION" ;;
    esac
fi

mkdir -p "$BIN_DIR"
install -m 755 "$TMP_FILE" "$BIN_DIR/vimb"

msg "已安装到 $BIN_DIR/vimb ($GOT_VERSION, ref=$REF)"
if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; then
    msg "文件 SHA-256: $(sha256_file "$BIN_DIR/vimb")"
fi

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        msg "提示: $BIN_DIR 不在 PATH 中，请将以下内容加入 shell 配置文件:"
        printf '         export PATH="%s:$PATH"\n' "$BIN_DIR"
        ;;
esac

# ---------------------------------------------------------------------------
# shell 别名：Android 构建环境（source build/envsetup.sh 后）经 out/.path 拦截
# 白名单外的命令（含 vimb 自身），用绝对路径别名绕过；vimb 2.4.1+ 启动时会
# 自行剔除 PATH 中的 */out/.path 段，vim/git 等子进程不受影响。
# 别名块由安装器托管（vimb-installer:begin/end 标记），重复安装自动更新而非追加。
install_shell_alias() { # install_shell_alias <vimb 绝对路径>
    local target=$1 rc_file='' block tmp action
    [ -n "${HOME:-}" ] || { msg "提示: 未设置 HOME，跳过 shell 别名配置"; return 0; }
    case "${SHELL:-bash}" in
        */zsh) rc_file=$HOME/.zshrc ;;
        */fish)
            msg "提示: 检测到 fish shell，请自行创建别名: alias vimb '$target'"
            return 0
            ;;
        *) rc_file=$HOME/.bashrc ;;
    esac
    block="# vimb-installer:begin
# Android 构建环境（source build/envsetup.sh 后）经 out/.path 拦截白名单外命令（含 vimb），
# 用绝对路径别名绕过；vimb 启动时会自行剔除 PATH 中的 */out/.path 段
alias vimb='$target'
# vimb-installer:end"
    tmp=$(mktemp "${TMPDIR:-/tmp}/vimb-rc.XXXXXX")
    if [ -f "$rc_file" ] && grep -qF '# vimb-installer:begin' "$rc_file"; then
        action=更新
        sed "/^# vimb-installer:begin\$/,/^# vimb-installer:end\$/d" "$rc_file" >"$tmp"
    else
        action=添加
        if [ -f "$rc_file" ]; then
            cat "$rc_file" >"$tmp"
        fi
    fi
    if [ -s "$tmp" ] && [ "$(tail -c1 "$tmp")" != '' ]; then
        printf '\n' >>"$tmp"
    fi
    printf '%s\n' "$block" >>"$tmp"
    if cat "$tmp" >"$rc_file" 2>/dev/null; then
        msg "已$action shell 别名到 $rc_file: alias vimb='$target'"
    else
        msg "提示: 无法写入 $rc_file，请手动添加: alias vimb='$target'"
    fi
    rm -f "$tmp"
}

case "$BIN_DIR" in
    /*) alias_target=$BIN_DIR/vimb ;;
    *)  alias_target=$PWD/$BIN_DIR/vimb ;;
esac
install_shell_alias "$alias_target"

msg "完成。运行 vimb --help 查看用法；vimb --update 可自更新到最新版本。"
