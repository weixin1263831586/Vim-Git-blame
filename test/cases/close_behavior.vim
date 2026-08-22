" close：关闭源文件窗口后 vimb 应整体退出（一次 :q 离开）
call assert_notequal(0, VimbTestBufWin('\[vimb-blame\]'), 'blame 应已打开')
let s:fw = VimbTestFileWin()
call assert_notequal(0, s:fw, '应能找到源文件窗口')

" 先写结果再关窗口：之后 vim 应自动退出，run.sh 检查退出码与结果文件
VimbTestFinish
call win_execute(s:fw, 'q')
" 若 vimb 未自动退出，这里兜底退出（此时用例仍算失败需超时/异常暴露），
" 但正常路径不会执行到这里。
qall!
