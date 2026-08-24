" 当前文件已 rename：Enter 必须按 blame record 的历史文件名显示该提交。
let s:fw = VimbTestFileWin()
call win_execute(s:fw, 'normal! 2G')
call VimbTestKey(s:fw, '\<CR>')
VimbWait
let s:cb = VimbTestCommitBufnr()
call assert_notequal(-1, s:cb, 'Enter 后应打开 commit 面板')
call assert_equal('old_name.txt', getbufvar(s:cb, 'vimb_path', ''),
            \ 'rename 前的 blame record 应使用旧文件名')
call assert_true(match(getbufline(s:cb, 1, '$'), 'old_name.txt') >= 0,
            \ '单文件 patch 应包含旧文件名')

" f 切到全部文件再切回时，仍须保留 record 的历史路径。
let s:cw = VimbTestBufWin('\[vimb-commit\]')
call VimbTestKey(s:cw, 'f')
VimbWait
call VimbTestKey(s:cw, 'f')
VimbWait
let s:cb = VimbTestCommitBufnr()
call assert_equal(1, getbufvar(s:cb, 'vimb_file_only'),
            \ '第二次 f 应回到单文件范围')
call assert_equal('old_name.txt', getbufvar(s:cb, 'vimb_path', ''),
            \ '切换范围不得丢失历史路径')
call assert_true(match(getbufline(s:cb, 1, '$'), 'old_name.txt') >= 0,
            \ '切回单文件后仍应显示旧路径 patch')
VimbTestFinish
qall!
