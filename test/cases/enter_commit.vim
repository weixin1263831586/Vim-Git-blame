" enter：文件窗口 Enter 打开 commit，f 切换范围，q 返回
let s:fw = VimbTestFileWin()
call assert_notequal(0, s:fw)
call win_execute(s:fw, 'normal! 1G')
call win_execute(s:fw, 'execute "normal \<CR>"')
VimbWait
let s:cb = VimbTestCommitBufnr()
call assert_notequal(-1, s:cb, 'Enter 后应打开 commit 窗口')
let s:lines = getbufline(s:cb, 1, '$')
call assert_true(match(s:lines, 'Author:') >= 0, 'commit 内容应含 Author:')
call assert_true(match(s:lines, 'Bob Builder\|Alice Author') >= 0, 'commit 内容应含作者名')
call assert_equal(1, getbufvar(s:cb, 'vimb_file_only'), '默认仅此文件')

" f 切换到全部文件
let s:cw = VimbTestBufWin('\[vimb-commit\]')
call win_execute(s:cw, 'execute "normal f"')
VimbWait
call assert_equal(0, getbufvar(VimbTestCommitBufnr(), 'vimb_file_only'), 'f 后应为全部文件')
let s:lines2 = getbufline(VimbTestCommitBufnr(), 1, '$')
call assert_true(match(s:lines2, '全部文件') >= 0, '标题应显示全部文件')

" q 返回源文件
call win_execute(VimbTestBufWin('\[vimb-commit\]'), 'execute "normal q"')
call assert_equal(-1, VimbTestCommitBufnr(), 'q 后 commit 窗口应关闭')
call assert_notequal(0, VimbTestFileWin(), '源文件窗口应仍在')
VimbTestFinish
qall!
