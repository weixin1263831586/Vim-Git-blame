" stack_close_async_race：Tab 后立即 gb，晚到回调不得重新切换源缓冲区。
let s:fw = VimbTestFileWin()
let s:orig_buf = winbufnr(s:fw)
call win_execute(s:fw, 'normal! 3G')
call VimbTestKey(s:fw, '\<Tab>')
call VimbTestKey(s:fw, 'gb')
VimbWait
sleep 100m
call assert_equal(0, VimbTestBufWin('\[vimb-blame\]'), 'gb 后 blame 应保持关闭')
call assert_equal(s:orig_buf, winbufnr(s:fw),
            \ '失效 Tab 回调不得把源窗口切回历史缓冲区')
VimbTestFinish
qall!
