" line_history_stack：历史层 gl 必须从当前 revision 起算
let s:fw = VimbTestFileWin()
call win_execute(s:fw, 'normal! 2G')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
sleep 200m
VimbWait
" 现在处于历史层（父版本，3 行且第 2 行为修改行）
call assert_match('vimb-src', bufname(winbufnr(s:fw)), '应在历史层')
call VimbTestKey(s:fw, 'gl')
VimbWait
let s:hb = bufnr('\[vimb-history\]')
call assert_notequal(-1, s:hb, 'gl 应打开行历史')
let s:lines = getbufline(s:hb, 1, '$')
" 行历史应从当前 revision（修改提交）开始，而不是 HEAD 的新文件
call assert_true(len(s:lines) > 5, '行历史应有内容')
VimbTestFinish
qall!
