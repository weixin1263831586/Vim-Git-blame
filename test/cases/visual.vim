" visual：连续 commit 合并显示、年龄热力组存在、compact 状态栏
let s:bb = VimbTestBlameBufnr()
let s:lines = getbufline(s:bb, 1, '$')
call assert_equal(6, len(s:lines))

" 连续相同 commit 的行：hash/author/date 留空，只显示行号
call assert_true(match(s:lines[0], '^ed98\|^[0-9a-f]\{10\} ') == 0
            \ || s:lines[0] =~# '^\S\{10\} ', '第 1 行应有 hash')
call assert_true(s:lines[2] =~# '^ \{10\} \{12\}', '第 3 行（同块）应只留行号: ' . s:lines[2])
" 块首行应有作者与日期
call assert_true(s:lines[1] =~# 'Bob Builder', '块首行应显示作者')
call assert_true(s:lines[1] =~# '2021-06-15', '块首行应显示日期')
" WORKTREE 行独立成块，显示 WORKTREE 标记
call assert_true(s:lines[5] =~# 'WORKTREE', '第 6 行应显示 WORKTREE')

" 年龄热力高亮组已定义（headless 无终端时 synIDattr 可能为空，只查组存在）
for s:g in ['VimbAge0', 'VimbAge1', 'VimbAge2', 'VimbAge3']
    call assert_true(hlID(s:g) > 0, s:g . ' 高亮组应已定义')
endfor

" compact 状态栏：源窗口状态栏显示当前行 commit 摘要
" （win_execute 内 normal 不触发 CursorMoved，用 feedkeys 驱动真实移动）
let s:fw = VimbTestFileWin()
call win_execute(s:fw, 'normal! 2G')
call win_execute(s:fw, 'doautocmd CursorMoved')
call win_execute(s:fw, 'let g:stl = &l:statusline')
call assert_true(match(g:stl, 'Bob Builder') >= 0,
            \ '状态栏应显示当前行作者: ' . g:stl)
call assert_true(match(g:stl, 'change middle lines') >= 0,
            \ '状态栏应显示当前行提交说明')

" WORKTREE 行状态栏
call win_execute(s:fw, 'normal! 6G')
call win_execute(s:fw, 'doautocmd CursorMoved')
call win_execute(s:fw, 'let g:stl2 = &l:statusline')
call assert_true(match(g:stl2, 'WORKTREE') >= 0, 'WORKTREE 行状态栏应有标记')

" gb 关闭后状态栏恢复为空（原样）
call VimbTestKey(s:fw, 'gb')
call win_execute(s:fw, 'let g:stl3 = &l:statusline')
call assert_equal('', g:stl3, '关闭 blame 后状态栏应恢复')
VimbTestFinish
qall!
