" stack_mixed_insert_modify：1→2 mixed hunk 中修改行必须追到旧 target。
let s:fw = VimbTestFileWin()
call win_execute(s:fw, 'normal! 3G')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
let s:line = VimbTestFileLine()
call assert_equal(2, s:line, 'target_changed 的 parent 行应为第 2 行')
call assert_equal('target',
            \ get(getbufline(winbufnr(s:fw), s:line, s:line), 0, ''),
            \ 'mixed hunk 修改行必须追溯到旧 target，而非判作首次引入')
VimbTestFinish
qall!
