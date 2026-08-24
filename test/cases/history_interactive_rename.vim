" history_interactive_rename：history Tab 必须使用所选 revision 当时的旧路径。
let s:fw = VimbTestFileWin()
call VimbTestKey(s:fw, 'gh')
VimbWait
let s:hb = bufnr('\[vimb-history\]')
let s:hw = bufwinid(s:hb)
let s:lines = getbufline(s:hb, 1, '$')
let s:index = match(s:lines, 'modify second line')
call assert_true(s:index >= 0, '应找到 rename 前的修改提交')
let s:record = get(getbufvar(s:hb, 'vimb_history_records', []), s:index, {})
call assert_equal('old_name.txt', get(s:record, 'path', ''),
            \ 'rename 前历史记录必须保存旧路径')
call win_execute(s:hw, 'call cursor(' . (s:index + 1) . ', 1)')
call VimbTestKey(s:hw, '\<Tab>')
VimbWait
call assert_match('old_name', bufname(winbufnr(s:fw)),
            \ 'history Tab 应进入 rename 前的旧路径缓冲区')
call assert_equal(3, len(VimbTestRecords()), '旧路径 revision 应有 3 行')
VimbTestFinish
qall!
