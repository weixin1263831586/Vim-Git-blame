#!/usr/bin/env bash
# vimb 回归测试：构造临时 Git fixture 仓库，用 headless vim 逐用例断言。
# 用法: bash test/run.sh [用例名 ...]   （不传参数则跑全部）
# 环境变量:
#   VIMB_SYNC=1   强制 vimb 走同步 Git 路径再跑一遍（异步路径为默认）

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VIMB="$ROOT/vimb"
CASES_DIR="$ROOT/test/cases"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/vimb-test.XXXXXX")
FIXTURE="$WORK/repo"
RESULTS="$WORK/results"
mkdir -p "$RESULTS"

pass=0
fail=0
failed_names=''

log() { printf '%s\n' "$*"; }

mgit() { git -C "$FIXTURE" "$@"; }

# ---------------------------------------------------------------------------
# fixture：一个包含各种边界情况的 Git 仓库
# ---------------------------------------------------------------------------
build_fixture() {
    git init "$FIXTURE" >/dev/null
    mgit config user.name 'Alice Author'
    mgit config user.email 'alice@example.com'
    mgit config commit.gpgsign false
    mgit config core.autocrlf false

    with_env() { # with_env <日期> <作者> <邮箱> <git 子命令及参数...>
        local date=$1 name=$2 email=$3
        shift 3
        GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
            git -C "$FIXTURE" -c user.name="$name" -c user.email="$email" "$@"
    }

    # code.c：A 提交 5 行，B 提交改 2-3 行，工作区再追加 1 行未提交
    printf 'alpha one\nalpha two\nalpha three\nalpha four\nalpha five\n' >"$FIXTURE/code.c"
    mgit add code.c
    with_env '2020-01-01T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -q -m 'initial code'
    printf 'alpha one\nbeta two\nbeta three\nalpha four\nalpha five\n' >"$FIXTURE/code.c"
    mgit add code.c
    with_env '2021-06-15T00:00:00' 'Bob Builder' 'bob@example.com' \
        commit -q -m 'change middle lines'
    printf 'alpha one\nbeta two\nbeta three\nalpha four\nalpha five\nuncommitted six\n' \
        >"$FIXTURE/code.c"

    # rename：old_name.txt（先加一行内容再）→ new_name.txt
    printf 'r line 1\nr line 2\n' >"$FIXTURE/old_name.txt"
    mgit add old_name.txt
    with_env '2020-02-02T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -m 'add old_name'
    printf 'r line 1\nr line 2\nr line 3 added later\n' >"$FIXTURE/old_name.txt"
    mgit add old_name.txt
    with_env '2020-02-03T00:00:00' 'Dana Dev' 'dana@example.com' \
        commit -m 'extend old_name'
    mgit mv old_name.txt new_name.txt
    with_env '2022-03-03T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -m 'rename to new_name'

    # 各种边界文件
    printf '中文一\n中文二\n' >"$FIXTURE/中文文件名.txt"
    printf 'sp one\nsp two\n' >"$FIXTURE/file with spaces.txt"
    : >"$FIXTURE/empty.txt"
    printf 'crlf one\r\ncrlf two\r\n' >"$FIXTURE/crlf.txt"
    printf 'ref one\nref two\n' >"$FIXTURE/refresh_target.txt"
    mgit add 中文文件名.txt 'file with spaces.txt' empty.txt crlf.txt refresh_target.txt
    with_env '2022-04-04T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -q -m 'add edge case files'

    # 大文件：20000 行，两个 commit
    seq 1 20000 | sed 's/^/line /' >"$FIXTURE/big.txt"
    mgit add big.txt
    with_env '2019-05-05T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -q -m 'add big file'
    seq 4996 5005 | sed 's/^/line /' | while read -r l; do
        printf '%s changed\n' "$l"
    done >"$FIXTURE/.big_patch"
    # 把 4996..5005 行改成 "line N changed"
    awk 'NR>=4996 && NR<=5005 {print $0 " changed"; next} {print}' \
        "$FIXTURE/big.txt" >"$FIXTURE/.big_new"
    mv "$FIXTURE/.big_new" "$FIXTURE/big.txt"
    rm -f "$FIXTURE/.big_patch"
    mgit add big.txt
    with_env '2023-07-07T00:00:00' 'Carol Changer' 'carol@example.com' \
        commit -q -m 'change middle of big file'

    # 远端（供 o 键 URL 构造测试；本地占位即可）
    mgit remote add origin git@github.com:example/vimb-test.git
}

# ---------------------------------------------------------------------------
# 用例运行
# ---------------------------------------------------------------------------
run_case() { # run_case <名称> <文件> <用例脚本> [noauto] [额外env]
    local name=$1 file=$2 script=$3 mode=${4:-} extra=${5:-}
    [ -f "$FIXTURE/$file" ] || { log "SKIP $name (fixture 缺少 $file)"; return; }

    local out="$RESULTS/$name.out"
    rm -f "$out"

    local -a env=(VIMB_TEST_OUT="$out"
        VIMB_TEST_CMDS="so $CASES_DIR/_common.vim
so $CASES_DIR/$script")
    if [ "$mode" = "noauto" ]; then
        env+=(VIMB_NO_AUTO_OPEN=1)
    fi
    if [ -n "$extra" ]; then
        env+=("$extra")
    fi

    local rc=0
    timeout 60 env "${env[@]}" "$VIMB" "$FIXTURE/$file" </dev/null >/dev/null 2>&1 || rc=$?

    if [ "$rc" -eq 124 ]; then
        log "FAIL $name (超时)"
        fail=$((fail + 1))
        failed_names="$failed_names $name"
        return
    fi
    if [ ! -f "$out" ]; then
        log "FAIL $name (无结果文件, rc=$rc)"
        fail=$((fail + 1))
        failed_names="$failed_names $name"
        return
    fi
    if [ "$(head -1 "$out")" = 'PASS' ]; then
        log "PASS $name"
        pass=$((pass + 1))
    else
        log "FAIL $name"
        sed 's/^/    /' "$out"
        fail=$((fail + 1))
        failed_names="$failed_names $name"
    fi
}

ALL_CASES='basic:code.c:basic.vim:
spaces:file with spaces.txt:spaces.vim:
utf8:中文文件名.txt:utf8.vim:
empty:empty.txt:empty.vim:
crlf:crlf.txt:crlf.vim:
worktree:code.c:worktree.vim:
rename:new_name.txt:rename.vim:
big:big.txt:big.vim:
enter:code.c:enter_commit.vim:
refresh:refresh_target.txt:refresh.vim:
toggle:code.c:toggle_restore.vim:noauto
fold:code.c:fold.vim:noauto
close:code.c:close_behavior.vim:
stack:code.c:stack.vim:
stack_rename:new_name.txt:stack_rename.vim:
keys:code.c:keys.vim:
history:code.c:history.vim:
blameargs:code.c:blameargs.vim::VIMB_BLAME_ARGS=-w
visual:code.c:visual.vim:'

# ALL_CASES 为冒号分隔的多行串：名称:文件:用例脚本[:noauto[:额外env]]
run_all() {
    local line name file script mode extra
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        name=${line%%:*}
        local rest=${line#*:}
        file=${rest%%:*}
        rest=${rest#*:}
        script=${rest%%:*}
        rest=${rest#*:}
        mode=${rest%%:*}
        case "$rest" in
            *:*) extra=${rest#*:} ;;
            *)   extra='' ;;
        esac
        if [ "$#" -gt 0 ]; then
            local want=0
            for filter in "$@"; do
                [ "$filter" = "$name" ] && want=1
            done
            [ "$want" -eq 0 ] && continue
        fi
        run_case "$name" "$file" "$script" "$mode" "$extra"
    done <<<"$ALL_CASES"
}

log "=== vimb 回归测试 ==="
log "fixture: $FIXTURE"
build_fixture
run_all "$@"

log "=== 结果: $pass 通过, $fail 失败 ==="
if [ "$fail" -gt 0 ]; then
    log "失败用例:$failed_names"
    exit 1
fi
exit 0
