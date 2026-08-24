" compact statusline 必须按字符/显示宽度裁剪，不得截断 UTF-8 字节。
let s:fw = VimbTestFileWin()
call win_execute(s:fw, 'normal! 1G')
call VimbTestKey(s:fw, 'l')
call VimbTestKey(s:fw, 'h')
let s:statusline = getwinvar(s:fw, '&statusline')
call assert_match('…$', s:statusline,
            \ '超长中文 summary 应以完整省略号结束')
call assert_equal(s:statusline, iconv(s:statusline, 'utf-8', 'utf-8'),
            \ '状态栏应保持有效 UTF-8')
VimbTestFinish
qall!
