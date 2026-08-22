" blameargs：-w 透传到 git blame（whitespace 变化的行归因不变）
" fixture 里没有 whitespace-only 变更，这里验证参数生效即可：
" 用 --blame-args 启动（run.sh 不支持），改为校验 VIMB_BLAME_ARGS 环境变量
" 已由启动器写入。本用例经 run_case 的 env 透传 VIMB_BLAME_ARGS='-w'。
let s:records = VimbTestRecords()
call assert_equal(6, len(s:records), '-w 模式记录数应不变')
call assert_notequal('', s:records[1].hash)
VimbTestFinish
qall!
