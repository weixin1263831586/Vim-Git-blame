" visual_big_256：20k 行 256 色路径只能按连续 commit 块建 region。
set t_Co=256
VimbToggle
VimbWait
let s:bw = VimbTestBufWin('\[vimb-blame\]')
call assert_notequal(0, s:bw, 'blame 应打开')
call win_execute(s:bw, 'let g:vimb_syntax_dump = execute("syntax list")')
let s:regions = len(split(g:vimb_syntax_dump, 'start=/')) - 1
call assert_true(s:regions > 0, '256 色路径应定义 commit block region')
call assert_true(s:regions < 100,
            \ '20k 行不应创建逐行 region，实际数量=' . s:regions)
" fixture 最新一次提交是 2023-07-07；按当前真实时间计算已超过三年，
" 必须属于 Age3。旧的“相对文件最新提交”算法会错误归入 Age0。
call win_execute(s:bw,
            \ 'let g:vimb_age3_dump = execute("syntax list VimbAge3")')
call assert_true(stridx(g:vimb_age3_dump, '\%4996l') >= 0,
            \ '2023 提交应按真实代码年龄归入 Age3，而非相对文件年龄')
VimbTestFinish
qall!
