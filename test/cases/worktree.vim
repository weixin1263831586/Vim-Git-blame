" worktree：未提交行标记 WORKTREE，Enter 不打开 commit 面板
let s:records = VimbTestRecords()
call assert_equal(6, len(s:records))
call assert_true(s:records[5].hash =~# '^0\+$', '第 6 行应为 WORKTREE')

" 在文件窗口第 6 行按 Enter → 报错提示，不打开 commit 窗口
let s:fw = VimbTestFileWin()
call assert_notequal(0, s:fw, '应能找到源文件窗口')
call win_execute(s:fw, 'normal! 6G')
call win_execute(s:fw, 'execute "normal \<CR>"')
call assert_equal(-1, VimbTestCommitBufnr(), 'WORKTREE 行不应打开 commit 窗口')

" 在 blame 窗口第 6 行按 Enter → 同样不打开
let s:bw = VimbTestBufWin('\[vimb-blame\]')
call win_execute(s:bw, 'normal! 6G')
call win_execute(s:bw, 'execute "normal \<CR>"')
call assert_equal(-1, VimbTestCommitBufnr())
VimbTestFinish
qall!
