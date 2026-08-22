" utf8：中文文件名
call assert_notequal(0, VimbTestBufWin('\[vimb-blame\]'), 'blame 窗口应已打开')
let s:records = VimbTestRecords()
call assert_equal(2, len(s:records))
call assert_equal('中文一', s:records[0].text)
VimbTestFinish
qall!
