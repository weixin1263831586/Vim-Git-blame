" spaces：文件名含空格
call assert_notequal(0, VimbTestBufWin('\[vimb-blame\]'), 'blame 窗口应已打开')
let s:records = VimbTestRecords()
call assert_equal(2, len(s:records))
call assert_notequal('', s:records[0].hash)
call assert_true(s:records[0].hash !~# '^0\+$')
VimbTestFinish
qall!
