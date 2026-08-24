" History Explorer Tab 应追踪逻辑行，而不是照搬当前数字行号。
" HEAD 在目标行前新增一行：HEAD:3 对应所选修改提交的第 2 行。
let s:fw = VimbTestFileWin()
call win_execute(s:fw, 'normal! 3G')
call VimbTestKey(s:fw, 'gh')
VimbWait
let s:hb = bufnr('\[vimb-history\]')
let s:hw = bufwinid(s:hb)
let s:lines = getbufline(s:hb, 1, '$')
let s:index = match(s:lines, 'old shift modify target')
call assert_true(s:index >= 0, '应找到插入之前的修改提交')
call win_execute(s:hw, 'call cursor(' . (s:index + 1) . ', 1)')
call VimbTestKey(s:hw, '\<Tab>')
VimbWait
call assert_equal(2, VimbTestFileLine(),
            \ 'History Tab 应把 HEAD 第 3 行映射为历史版本第 2 行')
call assert_equal('target changed',
            \ get(getbufline(winbufnr(s:fw), 2, 2), 0, ''),
            \ '映射后应落在同一逻辑行')
VimbTestFinish
qall!
