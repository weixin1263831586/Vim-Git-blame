" stack_second_insertion：第二个 insertion hunk 的 new_start 已是 child 绝对行号。
let s:fw = VimbTestFileWin()
let s:orig_buf = winbufnr(s:fw)
call win_execute(s:fw, 'normal! 10G')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
call assert_equal(s:orig_buf, winbufnr(s:fw),
            \ '第二个纯新增 hunk 不得被误映射进父版本')
call assert_equal('NEW2', get(getbufline(s:orig_buf, 10, 10), 0, ''))
VimbTestFinish
qall!
