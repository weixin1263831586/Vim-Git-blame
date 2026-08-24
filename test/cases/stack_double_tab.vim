" stack_double_tab：追溯进行中第二次 Tab 应被忽略，只能入栈一层。
let s:fw = VimbTestFileWin()
let s:orig_buf = winbufnr(s:fw)
call win_execute(s:fw, 'normal! 3G')
call VimbTestKey(s:fw, '\<Tab>')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
call assert_notequal(s:orig_buf, winbufnr(s:fw), '第一次 Tab 应正常入栈')
call VimbTestKey(s:fw, '\<BS>')
VimbWait
call assert_equal(s:orig_buf, winbufnr(s:fw),
            \ '一次 Backspace 应回到工作区，证明没有重复入栈')
VimbTestFinish
qall!
