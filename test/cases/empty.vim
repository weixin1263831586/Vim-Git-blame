" empty：空文件无记录但不报错
call assert_notequal(0, VimbTestBufWin('\[vimb-blame\]'), 'blame 窗口应已打开')
call assert_equal(0, len(VimbTestRecords()), '空文件应无记录')
let s:blame_win = VimbTestBufWin('\[vimb-blame\]')
let s:first = getbufline(VimbTestBlameBufnr(), 1, 1)[0]
call assert_true(stridx(s:first, '空文件') >= 0, '应显示空文件提示: ' . s:first)
VimbTestFinish
qall!
