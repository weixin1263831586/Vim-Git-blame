#!/usr/bin/env bash
# vimb - a small, predictable Vim Git blame workspace.

set -euo pipefail

VERSION="2.4.1"

usage() {
    cat <<'EOF'
用法: vimb [-w] [-M] [-C] [--blame-args="<选项>"] [--] <文件>

在 Vim 中打开一个已被 Git 跟踪的文件，并在左侧显示逐行 blame 信息。

  -w / -M / -C        追加给 git blame 的选项：忽略空白 / 检测文件内移动 / 检测跨文件复制
  --blame-args=...    透传任意 git blame 选项，如 --blame-args="-w -M -C"
  -u, --update        从 GitHub 下载最新 vimb 并替换自身后退出

  鼠标单击 / Enter   查看该行所属 commit
  鼠标双击           原生选词，释放左键自动复制到剪贴板
  鼠标拖拽           原生选区，释放左键自动复制完整文本
  Tab / Backspace    向前追溯该行的历史 commit / 返回较新版本
  gh / gl            文件历史 / 当前行历史
  i                  轻量 commit 信息（作者/日期/previous）
  y                  复制当前 commit SHA
  o                  在浏览器打开 commit（GitHub/GitLab/Gerrit 等）
  f                  commit 面板内切换 仅此文件/全部文件
  q / Backspace       从 commit 返回原文件
  q                   在 blame 栏关闭 blame
  gb                  显示或隐藏 blame
  r / F5              刷新 blame
  ?                    显示快捷键提示

辅助面板都是只读临时缓冲区；vimb 只会打开命令行指定的文件。
文件名以 “-” 开头时，请使用: vimb -- <文件>
EOF
}

die() {
    printf 'vimb: %s\n' "$*" >&2
    exit 1
}

# Android 构建环境（source build/envsetup.sh 后）会把 <tree>/out/.path 插到
# PATH 最前做白名单拦截，白名单外的工具（vim、dirname 等）会被拒绝执行。
# 启动前剔除所有 */out/.path 拦截段，让 vimb 及其子进程走正常 PATH 解析；
# 非构建环境下没有任何 PATH 项命中该模式，此处等于无操作。
strip_path_interposers() {
    local cleaned='' entry
    local IFS=:
    for entry in $PATH; do
        case "$entry" in
            */out/.path) ;;
            *) cleaned="${cleaned:+$cleaned:}$entry" ;;
        esac
    done
    [ -n "$cleaned" ] || return 0
    PATH=$cleaned
    export PATH
}
strip_path_interposers

VIMB_REPO_RAW="https://raw.githubusercontent.com/weixin1263831586/Vim-Git-blame"
VIMB_REPO_API_TIP="https://api.github.com/repos/weixin1263831586/Vim-Git-blame/commits/main"

vimb_fetch() { # vimb_fetch <url>，内容写 stdout
    if command -v curl >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 -fsSL "$1"
    else
        wget -qO- "$1"
    fi
}

# 解析 main 最新提交的不可变 SHA；失败时返回非 0（调用方回退到 main 引用）。
vimb_latest_ref() {
    local json shas
    json=$(vimb_fetch "$VIMB_REPO_API_TIP" 2>/dev/null) || return 1
    shas=$(printf '%s\n' "$json" \
        | sed -n 's/.*"sha": *"\([0-9a-f]\{40\}\)".*/\1/p')
    [ -n "$shas" ] || return 1
    printf '%s\n' "${shas%%$'\n'*}"
}

# 自更新：下载最新 vimb 校验后原子替换自身。
# VIMB_UPDATE_URL 可覆盖下载地址（镜像/测试）；VIMB_UPDATE_REF 可固定来源 ref。
update_self() {
    command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
        || die "自更新需要 curl 或 wget 之一"

    local self=$0 ref='' url=${VIMB_UPDATE_URL:-} new_version
    case $self in
        /*) ;;
        *)  self=$(command -v -- "$self" 2>/dev/null || printf '%s\n' "$self") ;;
    esac
    if command -v readlink >/dev/null 2>&1; then
        local resolved
        if resolved=$(readlink -f -- "$self" 2>/dev/null) && [ -n "$resolved" ]; then
            self=$resolved
        fi
    fi
    [ -f "$self" ] || die "无法定位 vimb 自身路径: $0"

    if [ -z "$url" ]; then
        ref=${VIMB_UPDATE_REF:-}
        if [ -z "$ref" ]; then
            if ! ref=$(vimb_latest_ref); then
                ref=''
            fi
        fi
        [ -n "$ref" ] || {
            ref=main
            printf 'vimb: 无法访问 GitHub API，回退到可变引用 main\n' >&2
        }
        url="$VIMB_REPO_RAW/$ref/vimb"
    fi

    # 注意：EXIT trap 里的变量不能用 local——trap 在函数返回后才执行，
    # 局部变量届时已销毁（set -u 下会报 unbound），因此用全局名。
    VIMB_UPDATE_TMP=$(mktemp "${TMPDIR:-/tmp}/vimb-update.XXXXXX")
    trap 'rm -f -- "$VIMB_UPDATE_TMP"' EXIT
    if ! vimb_fetch "$url" >"$VIMB_UPDATE_TMP"; then
        die "下载失败: $url"
    fi

    head -1 "$VIMB_UPDATE_TMP" | grep -q '^#!/usr/bin/env bash' \
        || die "下载内容不是 vimb 脚本: $url"
    grep -q '^VERSION=' "$VIMB_UPDATE_TMP" \
        || die "下载内容不完整: $url"
    new_version=$(bash "$VIMB_UPDATE_TMP" --version 2>/dev/null) \
        || die "下载脚本无法执行，已放弃更新"
    case "$new_version" in
        'vimb '[0-9]*) ;;
        *) die "下载脚本版本异常: $new_version" ;;
    esac

    if cmp -s "$VIMB_UPDATE_TMP" "$self"; then
        printf 'vimb: 已是最新版本 %s\n' "${new_version#vimb }"
        return 0
    fi

    local dir=${self%/*} staged
    [ -d "$dir" ] && [ -w "$dir" ] \
        || die "无权限写入 $dir，请手动执行: install -m 755 <新版vimb> $self"
    staged=$(mktemp "$dir/.vimb.update.XXXXXX") \
        || die "在 $dir 创建临时文件失败"
    cat >"$staged" <"$VIMB_UPDATE_TMP"
    chmod 755 "$staged"
    if ! mv -f -- "$staged" "$self"; then
        rm -f -- "$staged"
        die "替换 $self 失败"
    fi
    printf 'vimb: 已更新 %s → %s\n' "$VERSION" "${new_version#vimb }"
    if [ -n "$ref" ]; then
        printf 'vimb: 来源 %s\n' "$ref"
    fi
    return 0
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    --version)
        printf 'vimb %s\n' "$VERSION"
        exit 0
        ;;
    -u|--update|--u)
        update_self
        exit 0
        ;;
esac

BLAME_EXTRA_ARGS=''
while [ $# -gt 0 ]; do
    case "$1" in
        -w|-M|-C)
            BLAME_EXTRA_ARGS="$BLAME_EXTRA_ARGS $1"
            shift
            ;;
        --blame-args)
            [ "$#" -ge 2 ] || die "--blame-args 需要参数"
            BLAME_EXTRA_ARGS="$BLAME_EXTRA_ARGS $2"
            shift 2
            ;;
        --blame-args=*)
            BLAME_EXTRA_ARGS="$BLAME_EXTRA_ARGS ${1#--blame-args=}"
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
    esac
done

[ "$#" -eq 1 ] || {
    usage >&2
    exit 2
}

INPUT_FILE=$1

# 尽力解析为绝对路径（不依赖 GNU realpath --relative-to）：
# readlink -f（Linux / macOS 12.3+）→ realpath → 纯 bash 词法归一化（不解析符号链接）
resolve_path() {
    local p=$1 out
    if out=$(readlink -f -- "$p" 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out"
        return 0
    fi
    if out=$(realpath -- "$p" 2>/dev/null) && [ -n "$out" ]; then
        printf '%s\n' "$out"
        return 0
    fi
    local -a parts=()
    local part norm=/
    case "$p" in
        /*) IFS=/ read -ra parts <<<"$p" ;;
        *)  IFS=/ read -ra parts <<<"$PWD/$p" ;;
    esac
    for part in "${parts[@]}"; do
        case "$part" in
            ''|.) ;;
            ..)
                norm=${norm%/}
                norm=${norm%/*}
                [ -z "$norm" ] && norm=/
                ;;
            *) norm="$norm$part/" ;;
        esac
    done
    printf '%s\n' "${norm%/}"
}

FILE=$(resolve_path "$INPUT_FILE")
[ -f "$FILE" ] || die "文件不存在: $INPUT_FILE"

FILE_DIR=$(dirname -- "$FILE")
if ! GIT_ROOT=$(git -C "$FILE_DIR" rev-parse --show-toplevel 2>/dev/null); then
    die "文件不在 Git 工作区中: $FILE"
fi
GIT_ROOT=$(resolve_path "$GIT_ROOT")
REL_PATH=${FILE#"$GIT_ROOT"/}
[ "$REL_PATH" != "$FILE" ] || die "文件不属于检测到的 Git 工作区: $FILE"

case "$REL_PATH" in
    ..|../*) die "文件不属于检测到的 Git 工作区: $FILE" ;;
esac

if ! git -C "$GIT_ROOT" ls-files --error-unmatch -- "$REL_PATH" >/dev/null 2>&1; then
    die "文件尚未被 Git 跟踪: $REL_PATH"
fi

command -v vim >/dev/null 2>&1 || die "未找到 vim"

VIM_SCRIPT=$(mktemp "${TMPDIR:-/tmp}/vimb.XXXXXX.vim")
trap 'rm -f -- "$VIM_SCRIPT"' EXIT

cat >"$VIM_SCRIPT" <<'VIMSCRIPT'
# @VIMB_VIMSCRIPT@
VIMSCRIPT

export VIMB_GIT_ROOT="$GIT_ROOT"
export VIMB_REL_PATH="$REL_PATH"
export VIMB_FILE="$FILE"
export VIMB_BLAME_ARGS="${BLAME_EXTRA_ARGS# }"

vim -N -S "$VIM_SCRIPT" -- "$FILE"
