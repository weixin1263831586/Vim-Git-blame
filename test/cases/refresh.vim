" refresh：保存文件后自动刷新 blame（BufWritePost）
let s:records = VimbTestRecords()
call assert_equal(2, len(s:records), '初始 2 行')

" 在源文件窗口追加一行并保存
let s:fw = VimbTestFileWin()
call win_execute(s:fw, 'call setline(3, "ref three")')
call win_execute(s:fw, 'write')
VimbWait
let s:records = VimbTestRecords()
call assert_equal(3, len(s:records), '保存后应刷新为 3 条记录')
call assert_true(s:records[2].hash =~# '^0\+$', '新行应为 WORKTREE')
VimbTestFinish
qall!
