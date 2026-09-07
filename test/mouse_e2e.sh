#!/usr/bin/env bash
# mouse_e2e：用 pty + 真实 SGR 鼠标序列端到端验证双击/拖拽复制。
# 不需要真实 X：PATH 中放置 xclip 替身记录剪贴板写入。
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
command -v python3 >/dev/null 2>&1 || { echo "SKIP mouse_e2e (无 python3)"; exit 0; }
[ "${VIMB_SYNC:-}" = "1" ] && { echo "SKIP mouse_e2e (VIMB_SYNC 重复跑)"; exit 0; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vimb-e2e.XXXXXX")
FIXTURE="$WORK/repo"
CLIPDIR="$WORK/clip"
mkdir -p "$FIXTURE" "$CLIPDIR" "$WORK/bin"

printf 'alpha one alpha two\nalpha three alpha four\n' \
    >"$FIXTURE/code.txt"

cat >"$WORK/bin/xclip" <<EOF
#!/bin/sh
# 测试用 xclip 替身：-in 时把 stdin 记录到 \$VIMB_FAKE_CLIP_DIR/<selection>
sel=clipboard
mode=in
while [ \$# -gt 0 ]; do
    case "\$1" in
        -selection) sel="\$2"; shift 2 ;;
        -in) mode=in; shift ;;
        -out) mode=out; shift ;;
        *) shift ;;
    esac
done
if [ "\$mode" = in ]; then
    tmp=\$(mktemp "\$VIMB_FAKE_CLIP_DIR/input.XXXXXX")
    cat >"\$tmp"
    [ "\$(cat "\$tmp")" = slow-clipboard-write ] && sleep 0.7
    mv "\$tmp" "\$VIMB_FAKE_CLIP_DIR/\$sel"
fi
exit 0
EOF
chmod +x "$WORK/bin/xclip"

# 慢速 git 垫身：blame 子命令延迟 0.9s，让异步刷新回调落在双击选区
# 保持期间（场景 7 的竞态回归）；show 延迟 2.5s 给场景 10 留足余量，
# 高负载下双击输入被延迟处理时回调也不会抢先在普通模式应用。
# 其他子命令不受影响。
mkdir -p "$WORK/slowbin"
cat >"$WORK/slowbin/git" <<'EOF'
#!/bin/sh
for arg in "$@"; do
    case "$arg" in
        blame) sleep 0.9 ;;
        show) sleep 2.5 ;;
    esac
done
exec /usr/bin/git "$@"
EOF
chmod +x "$WORK/slowbin/git"

env GIT_AUTHOR_DATE='2024-01-01T00:00:00' \
    GIT_COMMITTER_DATE='2024-01-01T00:00:00' \
    GIT_AUTHOR_NAME=Alice GIT_COMMITTER_NAME=Alice \
    GIT_AUTHOR_EMAIL=a@x.com GIT_COMMITTER_EMAIL=a@x.com \
    git -C "$FIXTURE" init -q .
git -C "$FIXTURE" add code.txt
git -C "$FIXTURE" -c commit.gpgsign=false commit -q -m initial

PATH="$WORK/bin:$WORK/slowbin:$PATH" VIMB="$ROOT/vimb" \
    VIMB_E2E_FIXTURE="$FIXTURE" VIMB_FAKE_CLIP_DIR="$CLIPDIR" \
    python3 "$ROOT/test/mouse_e2e.py"
rc=$?

rm -rf "$WORK"
exit "$rc"
