" history：gh 文件历史 / gl 行历史面板
let s:fw = VimbTestFileWin()

" gh：显示文件历史（每行 短hash|作者|日期|提交说明）
call VimbTestKey(s:fw, 'gh')
VimbWait
let s:hb = bufnr('\[vimb-history\]')
call assert_notequal(-1, s:hb, 'gh 应打开历史面板')
let s:lines = getbufline(s:hb, 1, '$')
call assert_true(len(s:lines) > 3, '文件历史应有内容')
call assert_true(match(s:lines, 'initial code') >= 0, '应包含 initial code 提交')
call assert_true(match(s:lines, 'change middle lines') >= 0,
            \ '应包含 change middle lines 提交')
" 按时间倒序：change middle lines 应在 initial code 之前
call assert_true(match(s:lines, 'change middle lines') < match(s:lines, 'initial code'),
            \ '历史应按时间倒序')

" q 关闭
let s:hw = bufwinid(s:hb)
call win_execute(s:hw, 'execute "normal q"')
call assert_equal(-1, bufnr('\[vimb-history\]'), 'q 应关闭历史面板')

" gl：第 2 行行历史（该行 2 个 commit：beta 修改 + alpha 初始）
call win_execute(s:fw, 'normal! 2G')
call VimbTestKey(s:fw, 'gl')
VimbWait
let s:hb2 = bufnr('\[vimb-history\]')
call assert_notequal(-1, s:hb2, 'gl 应打开行历史面板')
let s:lines2 = getbufline(s:hb2, 1, '$')
call assert_true(len(s:lines2) > 5, '行历史应有内容')
call assert_true(match(s:lines2, 'beta two') >= 0 || match(s:lines2, 'diff') >= 0,
            \ '行历史应含该行的 diff')
VimbTestFinish
qall!
