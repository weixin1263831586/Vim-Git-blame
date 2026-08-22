" rename 栈：new_name.txt 第 3 行 Tab 入栈后应显示旧路径 old_name.txt 的 blame
let s:fw = VimbTestFileWin()
let s:orig_buf = winbufnr(s:fw)
call win_execute(s:fw, 'normal! 3G')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
let s:records = VimbTestRecords()
call assert_equal(2, len(s:records), '入栈后应显示父版本（2 行）')
call assert_equal('Alice Author', s:records[1].author, '父版本第 2 行应属初始提交')
call assert_notequal(s:orig_buf, winbufnr(s:fw), '源窗口应切到历史缓冲区')
call assert_match('old_name', bufname(winbufnr(s:fw)),
            \ '历史缓冲区应基于旧文件名创建')
" commit 面板 f 的“仅此文件”应使用旧路径
call win_execute(s:fw, 'execute "normal \<CR>"')
VimbWait
let s:cb = VimbTestCommitBufnr()
call assert_notequal(-1, s:cb, 'Enter 应打开 commit 面板')
let s:lines = getbufline(s:cb, 1, '$')
call assert_true(match(s:lines, 'old_name') >= 0,
            \ 'commit 面板仅此文件模式应显示 old_name 的变更')
VimbTestFinish
qall!
