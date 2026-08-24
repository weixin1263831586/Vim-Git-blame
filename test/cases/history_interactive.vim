" history_interactive：文件历史 commit 行支持 y / Enter / Tab。
let s:fw = VimbTestFileWin()
let s:orig_buf = winbufnr(s:fw)
call VimbTestKey(s:fw, 'gh')
VimbWait
let s:hb = bufnr('\[vimb-history\]')
let s:hw = bufwinid(s:hb)
let s:lines = getbufline(s:hb, 1, '$')
let s:index = match(s:lines, 'initial code')
call assert_true(s:index >= 0, '应找到 initial code 历史记录')
let s:records = getbufvar(s:hb, 'vimb_history_records', [])
let s:record = get(s:records, s:index, {})
call assert_equal(40, strlen(get(s:record, 'hash', '')),
            \ '历史记录应保存完整 SHA')
call assert_equal('code.c', get(s:record, 'path', ''),
            \ '历史记录应保存该 revision 的文件路径')

" y：历史行直接复制完整 SHA。
call win_execute(s:hw, 'call cursor(' . (s:index + 1) . ', 1)')
call VimbTestKey(s:hw, 'y')
call assert_equal(s:record.hash, @", 'history y 应复制所选完整 SHA')

" Enter：打开所选 commit，然后 q 返回源窗口。
call VimbTestKey(s:hw, '\<CR>')
VimbWait
call assert_notequal(-1, VimbTestCommitBufnr(), 'history Enter 应打开 commit 面板')
call assert_equal(s:record.hash,
            \ getbufvar(VimbTestCommitBufnr(), 'vimb_hash', ''),
            \ 'commit 面板应显示所选历史记录')
call VimbTestKey(VimbTestBufWin('\[vimb-commit\]'), 'q')

" Tab：重新打开 history 后直接进入所选 revision，BS 一次回工作区。
call VimbTestKey(s:fw, 'gh')
VimbWait
let s:hb2 = bufnr('\[vimb-history\]')
let s:hw2 = bufwinid(s:hb2)
let s:lines2 = getbufline(s:hb2, 1, '$')
let s:index2 = match(s:lines2, 'initial code')
call win_execute(s:hw2, 'call cursor(' . (s:index2 + 1) . ', 1)')
call VimbTestKey(s:hw2, '\<Tab>')
VimbWait
call assert_match('vimb-src', bufname(winbufnr(s:fw)),
            \ 'history Tab 应进入所选 revision 的源码缓冲区')
call assert_equal(5, len(VimbTestRecords()), '所选 initial revision 应有 5 行')
call VimbTestKey(s:fw, '\<BS>')
VimbWait
call assert_equal(s:orig_buf, winbufnr(s:fw), '一次 BS 应回到工作区')
VimbTestFinish
qall!
