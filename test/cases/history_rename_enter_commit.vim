" History Explorer 的 Enter 必须把所选 revision 的旧路径传给 commit 面板。
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
            \ '历史记录应保存 revision 当时的旧路径')
call win_execute(s:hw, 'call cursor(' . (s:index + 1) . ', 1)')
call VimbTestKey(s:hw, '\<CR>')
VimbWait
let s:cb = VimbTestCommitBufnr()
call assert_notequal(-1, s:cb, 'history Enter 应打开 commit 面板')
call assert_equal(s:record.hash, getbufvar(s:cb, 'vimb_hash', ''),
            \ 'commit 面板应显示所选历史提交')
call assert_equal('old_name.txt', getbufvar(s:cb, 'vimb_path', ''),
            \ 'commit 面板应保留历史记录的旧路径')
call assert_true(match(getbufline(s:cb, 1, '$'), 'old_name.txt') >= 0,
            \ '历史提交单文件 patch 应包含旧文件名')
VimbTestFinish
qall!
