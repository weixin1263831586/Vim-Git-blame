" stack：Tab 入栈追溯历史版本，BS 逐层返回，gb 关闭后恢复原文件
let s:fw = VimbTestFileWin()
call assert_notequal(0, s:fw, '应找到源文件窗口')
let s:orig_buf = winbufnr(s:fw)

" 第 2 行属于第二个 commit（有 previous），Tab 入栈
call win_execute(s:fw, 'normal! 2G')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
let s:records = VimbTestRecords()
call assert_equal(5, len(s:records), '入栈后 blame 应显示父版本的 5 行')
call assert_equal('Alice Author', s:records[1].author,
            \ '父版本第 2 行应属于初始提交')
call assert_notequal(s:orig_buf, winbufnr(s:fw), '源窗口应切到历史版本缓冲区')
call assert_equal(2, VimbTestFileLine(),
            \ '入栈后源窗口应定位到 original_line（第 2 行）')

" BS 出栈：回到工作区层，源窗口切回真实文件
call VimbTestKey(s:fw, '\<BS>')
VimbWait
call assert_equal(s:orig_buf, winbufnr(s:fw), '出栈后源窗口应切回真实文件')
call assert_equal(6, len(VimbTestRecords()), '出栈后 blame 应回到工作区 6 行')
call assert_equal(2, VimbTestFileLine(),
            \ '出栈后源窗口应恢复到入栈前的行（第 2 行）')

" 第 1 行属于初始提交（无 previous），Tab 应提示且不入栈
call win_execute(s:fw, 'normal! 1G')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
call assert_equal(6, len(VimbTestRecords()), 'boundary 行 Tab 不应入栈')
call assert_equal(s:orig_buf, winbufnr(s:fw), 'boundary 行 Tab 不应切换缓冲区')

" WORKTREE 行同样不可入栈
call win_execute(s:fw, 'normal! 6G')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
call assert_equal(6, len(VimbTestRecords()), 'WORKTREE 行 Tab 不应入栈')
VimbTestFinish
qall!
