" crlf：CRLF 行尾文件
call assert_notequal(0, VimbTestBufWin('\[vimb-blame\]'), 'blame 窗口应已打开')
let s:records = VimbTestRecords()
call assert_equal(2, len(s:records), 'CRLF 文件行数应正确')
VimbTestFinish
qall!
