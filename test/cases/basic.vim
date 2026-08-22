" basic：code.c 打开后 blame 自动出现，记录数与内容正确
call assert_notequal(0, VimbTestBufWin('\[vimb-blame\]'), 'blame 窗口应已打开')
let s:records = VimbTestRecords()
call assert_equal(6, len(s:records), '应有 6 条记录（5 已提交 + 1 未提交）')
call assert_equal(1, s:records[0].final_line)
call assert_notequal('', s:records[0].author, '应解析出作者')
call assert_notequal('', s:records[0].summary, '应解析出提交说明')
call assert_notequal(0, s:records[0].author_time, '应解析出时间')
" 第 2、3 行属于第二个 commit，作者应为 Bob，且带 previous（父提交同文件）
call assert_equal('Bob Builder', s:records[1].author)
call assert_equal(s:records[1].hash, s:records[2].hash)
call assert_notequal('', s:records[1].previous, '修改行应有 previous 哈希')
call assert_equal('code.c', s:records[1].previous_path, 'previous_path 应为父提交路径')
call assert_equal('code.c', s:records[1].filename, 'filename 应为当前路径')
call assert_notequal('', s:records[1].author_mail, '应解析 author_mail')
" 第 1 行归因于初始提交（文件创建），无 previous
call assert_equal('', s:records[0].previous, '初始行不应有 previous')
" 未提交行 hash 全 0
call assert_true(s:records[5].hash =~# '^0\+$', '第 6 行应为 WORKTREE')
VimbTestFinish
qall!
