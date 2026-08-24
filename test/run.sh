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
    printf 'r line 1\nr line 2 MODIFIED\nr line 3 added later\n' >"$FIXTURE/old_name.txt"
    mgit add old_name.txt
    with_env '2020-02-04T00:00:00' 'Eve Editor' 'eve@example.com' \
        commit -m 'modify second line'
    mgit mv old_name.txt new_name.txt
    with_env '2022-03-03T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -m 'rename to new_name'

    # line-shift 场景：父版本 3 行，子版本在头部插入 1 行（target 移到第 3 行）
    printf 'a\ntarget\nz\n' >"$FIXTURE/shift.txt"
    mgit add shift.txt
    with_env '2021-01-01T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -m 'shift base'
    printf 'new\na\ntarget2\nz\n' >"$FIXTURE/shift.txt"
    mgit add shift.txt
    with_env '2021-01-02T00:00:00' 'Bob Builder' 'bob@example.com' \
        commit -m 'shift insert head'

    # old-commit-shift：被 blame 的 A 提交之后，B 又在目标行前插入内容。
    # original_line 属于 A 坐标系，不能拿它去映射 P → HEAD。
    printf 'a\ntarget\nz\n' >"$FIXTURE/old_commit_shift.txt"
    mgit add old_commit_shift.txt
    with_env '2021-01-03T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -m 'old shift base'
    printf 'a\ntarget changed\nz\n' >"$FIXTURE/old_commit_shift.txt"
    mgit add old_commit_shift.txt
    with_env '2021-01-04T00:00:00' 'Bob Builder' 'bob@example.com' \
        commit -m 'old shift modify target'
    printf 'new before\na\ntarget changed\nz\n' >"$FIXTURE/old_commit_shift.txt"
    mgit add old_commit_shift.txt
    with_env '2021-01-05T00:00:00' 'Carol Changer' 'carol@example.com' \
        commit -m 'old shift later insertion'

    # second-insertion：同一 commit 的第二个纯插入 hunk，new_start 已包含
    # 第一个 hunk 的偏移，映射算法不得再次把累计 delta 加到 new_start。
    printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n' >"$FIXTURE/second_insertion.txt"
    mgit add second_insertion.txt
    with_env '2021-01-06T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -m 'second insertion base'
    printf 'NEW1\na\nb\nc\nd\ne\nf\ng\nh\nNEW2\ni\nj\n' \
        >"$FIXTURE/second_insertion.txt"
    mgit add second_insertion.txt
    with_env '2021-01-07T00:00:00' 'Bob Builder' 'bob@example.com' \
        commit -m 'two separate insertions'

    # mixed hunk：同一个 hunk 同时插入一行并修改原目标行。whole-file
    # header 是 1→2，只有 git log -L 能可靠识别 target_changed → target。
    printf 'A\ntarget\nB\n' >"$FIXTURE/mixed_hunk.txt"
    mgit add mixed_hunk.txt
    with_env '2021-01-08T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -m 'mixed hunk base'
    printf 'A\ninserted\ntarget_changed\nB\n' >"$FIXTURE/mixed_hunk.txt"
    mgit add mixed_hunk.txt
    with_env '2021-01-09T00:00:00' 'Bob Builder' 'bob@example.com' \
        commit -m 'mixed insert and modify'

    # deep history：用于验证 source-buffer LRU 淘汰及 Backspace 懒加载。
    printf 'deep 0\n' >"$FIXTURE/deep.txt"
    mgit add deep.txt
    with_env '2021-01-10T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -m 'deep 0'
    for n in 1 2 3; do
        printf 'deep %s\n' "$n" >"$FIXTURE/deep.txt"
        mgit add deep.txt
        with_env "2021-01-$((10 + n))T00:00:00" 'Bob Builder' 'bob@example.com' \
            commit -m "deep $n"
    done

    # UTF-8 rename 场景：中文旧名 → 中文新名
    printf 'u line 1\nu line 2\n' >"$FIXTURE/旧文件.c"
    mgit add 旧文件.c
    with_env '2021-02-01T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -m 'add utf8 old'
    printf 'u line 1\nu line 2 MODIFIED\n' >"$FIXTURE/旧文件.c"
    mgit add 旧文件.c
    with_env '2021-02-02T00:00:00' 'Frank Fixer' 'frank@example.com' \
        commit -m 'modify utf8 old'
    mgit mv 旧文件.c 新文件.c
    with_env '2021-02-03T00:00:00' 'Alice Author' 'alice@example.com' \
        commit -m 'rename utf8'

    # Gerrit SSH 远端场景（单独仓库，不设真实 origin）
    mkdir -p "$WORK/gerrit-repo"
    git init "$WORK/gerrit-repo" >/dev/null 2>&1
    git -C "$WORK/gerrit-repo" config user.name G
    git -C "$WORK/gerrit-repo" config user.email g@x.com
    printf 'g1\ng2\n' >"$WORK/gerrit-repo/g.txt"
    git -C "$WORK/gerrit-repo" add g.txt
    git -C "$WORK/gerrit-repo" commit -m ginit >/dev/null
    git -C "$WORK/gerrit-repo" remote add origin \
        ssh://huang@gerrit.example.com:29418/platform/frameworks/base

    # 各种边界文件（中文文件的作者为中文，作作者列显示宽度对齐回归）
    printf '中文一\n中文二\n' >"$FIXTURE/中文文件名.txt"
    printf 'sp one\nsp two\n' >"$FIXTURE/file with spaces.txt"
    : >"$FIXTURE/empty.txt"
    printf 'crlf one\r\ncrlf two\r\n' >"$FIXTURE/crlf.txt"
    printf 'ref one\nref two\n' >"$FIXTURE/refresh_target.txt"
    mgit add 中文文件名.txt 'file with spaces.txt' empty.txt crlf.txt refresh_target.txt
    with_env '2022-04-04T00:00:00' '张三丰' 'zhang@example.com' \
        commit -m 'X这是一个用于验证状态栏不会截断多字节字符的很长中文提交说明这是额外长度'

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
    case "$file" in
        /*) [ -f "$file" ] || { log "SKIP $name (缺少 $file)"; return; } ;;
        *)  [ -f "$FIXTURE/$file" ] || { log "SKIP $name (fixture 缺少 $file)"; return; }
            file="$FIXTURE/$file" ;;
    esac
    local target=$file

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
    timeout 60 env "${env[@]}" "$VIMB" "$target" </dev/null >/dev/null 2>&1 || rc=$?

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
utf8_align:中文文件名.txt:utf8_align.vim:
empty:empty.txt:empty.vim:
crlf:crlf.txt:crlf.vim:
worktree:code.c:worktree.vim:
rename:new_name.txt:rename.vim:
big:big.txt:big.vim:
enter:code.c:enter_commit.vim:
rename_current_enter_commit:new_name.txt:rename_current_enter_commit.vim:
refresh:refresh_target.txt:refresh.vim:
toggle:code.c:toggle_restore.vim:noauto
fold:code.c:fold.vim:noauto
close:code.c:close_behavior.vim:
stack:code.c:stack.vim:
stack_rename:new_name.txt:stack_rename.vim:
keys:code.c:keys.vim:
history:code.c:history.vim:
history_limit:deep.txt:history_limit.vim::VIMB_HISTORY_LIMIT=1
history_interactive:code.c:history_interactive.vim:
history_logical_line:old_commit_shift.txt:history_logical_line.vim:
history_interactive_rename:new_name.txt:history_interactive_rename.vim:
history_rename_enter_commit:new_name.txt:history_rename_enter_commit.vim:
blameargs:code.c:blameargs.vim::VIMB_BLAME_ARGS=-w
visual:code.c:visual.vim:
stack_line_shift:shift.txt:stack_line_shift.vim:
stack_new_line:shift.txt:stack_new_line.vim:
stack_old_commit_shift:old_commit_shift.txt:stack_old_commit_shift.vim:
stack_second_insertion:second_insertion.txt:stack_second_insertion.vim:
stack_mixed_insert_modify:mixed_hunk.txt:stack_mixed_insert_modify.vim:
history_cache_depth:deep.txt:history_cache_depth.vim::VIMB_HISTORY_CACHE_DEPTH=1
stack_close_async_race:old_commit_shift.txt:stack_close_async_race.vim:
stack_double_tab:old_commit_shift.txt:stack_double_tab.vim:
statusline_quotes_restore:code.c:statusline_quotes_restore.vim:noauto
statusline_utf8_summary:中文文件名.txt:statusline_utf8_summary.vim:
visual_big_256:big.txt:visual_big_256.vim:noauto
stack_utf8_rename:新文件.c:stack_utf8_rename.vim:
history_close_race:code.c:history_close_race.vim:
line_history_stack:code.c:line_history_stack.vim:
gerrit_remote:WORK/gerrit-repo/g.txt:gerrit_remote.vim:'

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
        run_case "$name" "${file//WORK\//$WORK/}" "$script" "$mode" "$extra"
    done <<<"$ALL_CASES"
}

log "=== vimb 回归测试 ==="
log "fixture: $FIXTURE"
build_fixture
run_all "$@"

# CLI：vimb -w -- -foo.c 形式（-- 在选项之后）
cli_dashdash() {
    local bad=$1
    local out rc=0
    out=$(cd "$FIXTURE" && env VIMB_TEST_OUT=/dev/null VIMB_TEST_CMDS='qall!' \
        timeout 15 "$VIMB" $bad -- code.c </dev/null 2>&1) || rc=$?
    if echo "$out" | grep -q '用法\|usage'; then
        log "FAIL cli_dashdash ($bad)"
        fail=$((fail + 1))
        failed_names="$failed_names cli_dashdash"
    else
        log "PASS cli_dashdash ($bad)"
        pass=$((pass + 1))
    fi
}
cli_dashdash '-w'

log "=== 结果: $pass 通过, $fail 失败 ==="
if [ "$fail" -gt 0 ]; then
    log "失败用例:$failed_names"
    exit 1
fi
exit 0
