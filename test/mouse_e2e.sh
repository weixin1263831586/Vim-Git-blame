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
    cat >"\$VIMB_FAKE_CLIP_DIR/\$sel" 2>/dev/null
fi
exit 0
EOF
chmod +x "$WORK/bin/xclip"

env GIT_AUTHOR_DATE='2024-01-01T00:00:00' \
    GIT_COMMITTER_DATE='2024-01-01T00:00:00' \
    GIT_AUTHOR_NAME=Alice GIT_COMMITTER_NAME=Alice \
    GIT_AUTHOR_EMAIL=a@x.com GIT_COMMITTER_EMAIL=a@x.com \
    git -C "$FIXTURE" init -q .
git -C "$FIXTURE" add code.txt
git -C "$FIXTURE" -c commit.gpgsign=false commit -q -m initial

PATH="$WORK/bin:$PATH" VIMB="$ROOT/vimb" \
    VIMB_E2E_FIXTURE="$FIXTURE" VIMB_FAKE_CLIP_DIR="$CLIPDIR" \
    python3 "$ROOT/test/mouse_e2e.py"
rc=$?

rm -rf "$WORK"
exit "$rc"
