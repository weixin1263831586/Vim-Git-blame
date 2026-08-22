" fold：blame 开关过程中 fold 状态保持
setlocal foldmethod=manual
VimbToggle
call assert_notequal(0, VimbTestBufWin('\[vimb-blame\]'))

let s:fw = VimbTestFileWin()
call win_execute(s:fw, '5,6fold')
call assert_notequal(-1, foldclosed(6), '应已建立 fold')

VimbToggle
call assert_equal(0, VimbTestBufWin('\[vimb-blame\]'), 'blame 应关闭')
call assert_notequal(-1, foldclosed(6), '关闭 blame 后 fold 应保持')
call win_execute(s:fw, 'normal! zR')
VimbTestFinish
qall!
