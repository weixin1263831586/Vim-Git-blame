" statusline_quotes_restore：带单引号表达式必须逐字恢复，且不改变 syntax off。
let s:fw = VimbTestFileWin()
let s:statusline = "%{get(g:, 'branch', '')}"
call win_execute(s:fw, 'let &l:statusline = ' . string(s:statusline))
syntax off
call assert_false(exists('g:syntax_on'), '测试前 syntax 应关闭')
VimbToggle
VimbWait
call assert_false(exists('g:syntax_on'), '打开 blame 不应全局启用 syntax')
VimbToggle
call win_execute(s:fw, 'let g:vimb_restored_statusline = &l:statusline')
call assert_equal(s:statusline, g:vimb_restored_statusline,
            \ '关闭 blame 后 statusline 必须逐字恢复')
call assert_false(exists('g:syntax_on'), '关闭 blame 后 syntax 应保持关闭')
VimbTestFinish
qall!
