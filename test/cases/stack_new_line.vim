" stack_new_line：本次 commit 新增的行（previous 存在但 diff old_count=0）
" Tab 不得进入 parent，提示首次引入
let s:fw = VimbTestFileWin()
let s:orig_buf = winbufnr(s:fw)
call win_execute(s:fw, 'normal! 1G')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
sleep 200m
VimbWait
call assert_equal(s:orig_buf, winbufnr(s:fw),
            \ '新增行 Tab 不应入栈（不得追到无关旧行）')
call assert_equal(4, len(VimbTestRecords()), 'blame 行数不应变化')
VimbTestFinish
qall!
