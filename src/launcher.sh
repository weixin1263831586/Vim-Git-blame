#!/usr/bin/env bash
# vimb - a small, predictable Vim Git blame workspace.

set -euo pipefail

VERSION="2.3.0"

usage() {
    cat <<'EOF'
用法: vimb [-w] [-M] [-C] [--blame-args="<选项>"] [--] <文件>

在 Vim 中打开一个已被 Git 跟踪的文件，并在左侧显示逐行 blame 信息。

  -w / -M / -C        追加给 git blame 的选项：忽略空白 / 检测文件内移动 / 检测跨文件复制
  --blame-args=...    透传任意 git blame 选项，如 --blame-args="-w -M -C"

  鼠标单击 / Enter   查看该行所属 commit
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

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
    --version)
        printf 'vimb %s\n' "$VERSION"
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
