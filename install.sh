#!/usr/bin/env bash
# vimb 安装脚本：从 GitHub 下载 vimb 并安装到 ~/.local/bin
# 用法: curl --proto '=https' --tlsv1.2 -fsSL \
#       https://raw.githubusercontent.com/weixin1263831586/Vim-Git-blame/main/install.sh | sh
# 可通过 BIN_DIR 环境变量覆盖安装目录，例如: BIN_DIR=/usr/local/bin sh install.sh

set -eu

REPO_RAW="https://raw.githubusercontent.com/weixin1263831586/Vim-Git-blame/main"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"

msg() { printf 'vimb-installer: %s\n' "$*"; }
die() { printf 'vimb-installer: %s\n' "$*" >&2; exit 1; }

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

TMP_FILE=$(mktemp "${TMPDIR:-/tmp}/vimb-install.XXXXXX")
trap 'rm -f -- "$TMP_FILE"' EXIT

msg "正在下载 vimb ..."
fetch "$REPO_RAW/vimb" >"$TMP_FILE"

# 校验下载内容确实是 vimb 脚本，避免把错误页面装进 PATH
head -1 "$TMP_FILE" | grep -q '^#!/usr/bin/env bash' \
    || die "下载内容不是 vimb 脚本，请检查网络后重试"
grep -q '^VERSION=' "$TMP_FILE" \
    || die "下载内容不完整，请检查网络后重试"

mkdir -p "$BIN_DIR"
install -m 755 "$TMP_FILE" "$BIN_DIR/vimb"

msg "已安装到 $BIN_DIR/vimb ($("$BIN_DIR/vimb" --version))"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *)
        msg "提示: $BIN_DIR 不在 PATH 中，请将以下内容加入 shell 配置文件:"
        printf '         export PATH="%s:$PATH"\n' "$BIN_DIR"
        ;;
esac

msg "完成。运行 vimb --help 查看用法。"
