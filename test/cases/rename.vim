" rename：rename 后的文件可正常 blame；porcelain 的 filename 是该行所属
" 提交当时的文件名（rename 前），这正是历史追溯需要的信息
call assert_notequal(0, VimbTestBufWin('\[vimb-blame\]'), 'blame 窗口应已打开')
let s:records = VimbTestRecords()
call assert_equal(3, len(s:records))
call assert_notequal('', s:records[0].hash)
call assert_equal('old_name.txt', s:records[0].filename,
            \ '行归因于 rename 前的提交，filename 应为当时的旧路径')
call assert_equal('r line 1', s:records[0].text, '内容应来自 rename 前的文件')
call assert_equal('Dana Dev', s:records[2].author, '第 3 行应属 extend 提交')
VimbTestFinish
qall!
