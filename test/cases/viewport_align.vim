" viewport_align：底部 commit 面板缩放窗口后，blame/source 仍逐行对齐。
let s:fw = VimbTestFileWin()
let s:bw = VimbTestBufWin('\[vimb-blame\]')
call assert_notequal(0, s:fw)
call assert_notequal(0, s:bw)

call win_execute(s:fw, 'normal! 10000Gzz')
call win_execute(s:fw, 'doautocmd CursorMoved')

" 模拟 scrollbind 在窗口重排时留下的一行相对偏移。打开 commit 必须消除它。
call win_execute(s:bw, 'setlocal noscrollbind | execute "normal! 1\<C-E>" | setlocal scrollbind')
call VimbTestKey(s:fw, "\<CR>")
VimbWait

let s:fv = {}
let s:bv = {}
call win_execute(s:fw, 'let b:vimb_test_view = winsaveview()')
let s:fv = getbufvar(winbufnr(s:fw), 'vimb_test_view', {})
call win_execute(s:bw, 'let b:vimb_test_view = winsaveview()')
let s:bv = getbufvar(winbufnr(s:bw), 'vimb_test_view', {})
call assert_equal(get(s:fv, 'topline', -1), get(s:bv, 'topline', -2),
            \ '打开 commit 后 blame/source topline 必须一致')
call assert_equal(get(s:fv, 'lnum', -1), get(s:bv, 'lnum', -2),
            \ '打开 commit 后 blame/source cursor line 必须一致')
VimbTestFinish
qall!
