" stack_old_commit_shift：目标行归因于 A，之后 B 在它之前插入一行。
" HEAD 第 3 行的 original_line=2 属于 A；正确映射是 A:2 → P:2。
let s:fw = VimbTestFileWin()
call win_execute(s:fw, 'normal! 3G')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
let s:line = VimbTestFileLine()
call assert_equal('target',
            \ get(getbufline(winbufnr(s:fw), s:line, s:line), 0, ''),
            \ 'Tab 必须按 blame commit 坐标映射到 P 的 target 行')
call assert_equal(2, s:line, '父版本 target 应位于第 2 行')
VimbTestFinish
qall!
