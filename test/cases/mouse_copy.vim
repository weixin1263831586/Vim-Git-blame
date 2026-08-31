" mouse_copy：原生鼠标选择 + Visual 释放自动复制。
" 双击/三击/拖拽的选区本身交给 Vim 原生逻辑，vimb 只在 Visual 模式
" 释放左键时把 '< '> 标记的选区复制出去；这里同时验证映射形态与核心函数。
let s:fw = VimbTestFileWin()
let s:bw = VimbTestBufWin('\[vimb-blame\]')

for s:w in [s:fw, s:bw]
    " <2-LeftMouse> 不得被映射覆盖：双击选词必须保持 Vim 原生行为
    call win_execute(s:w, 'let b:vimb_double_map = maparg("<2-LeftMouse>", "n", 0, 1)')
    let s:m = getbufvar(winbufnr(s:w), 'vimb_double_map', {})
    call assert_true(empty(s:m),
                \ '源码和 blame 的双击选词不得被映射覆盖（保持原生行为）')
    " Visual 模式的 4 种释放事件都要映射到统一复制入口
    for s:ev in ['<LeftRelease>', '<2-LeftRelease>', '<3-LeftRelease>',
                \ '<4-LeftRelease>']
        call win_execute(s:w,
                    \ 'let b:vimb_release_map = maparg("' . s:ev . '", "v", 0, 1)')
        let s:release = getbufvar(winbufnr(s:w), 'vimb_release_map', {})
        call assert_true(get(s:release, 'rhs', '') =~# 'CopyMouseSelection',
                    \ '源码和 blame 都应映射 ' . s:ev . ' 到释放复制')
    endfor
endfor

" 释放复制核心：viw 选词 + Esc（模拟 release 映射里 Ex 命令把选区转成
" '< '> 标记并退出 Visual 的真实路径）→ 复制 → 保持选区高亮。
call win_gotoid(s:fw)
call cursor(1, 3)
execute "normal! viw\<Esc>"
VimbCopyMouseSelection
call assert_equal('alpha', @", '双击单词后释放应复制 alpha')
call assert_equal('v', mode(), '复制完成后应保持可见字符选区')
execute "normal! \<Esc>"

" 多行拖拽：从第 1 行 one 开头拖到第 2 行 beta 前缀（1:7 → 2:4）。
call cursor(1, 7)
execute "normal! v"
call cursor(2, 4)
execute "normal! \<Esc>"
VimbCopyMouseSelection
call assert_equal("one\nbeta", @", '拖拽释放应复制完整多行选区')
call assert_equal('v', mode(), '拖拽复制完成后应保持 Visual 高亮')
execute "normal! \<Esc>"

call VimbTestKey(s:fw, "\<CR>")
VimbWait
let s:cw = VimbTestBufWin('\[vimb-commit\]')
call assert_notequal(0, s:cw, '应打开 commit 面板')
call win_execute(s:cw, 'let b:vimb_double_map = maparg("<2-LeftMouse>", "n", 0, 1)')
let s:cm = getbufvar(winbufnr(s:cw), 'vimb_double_map', {})
call assert_true(empty(s:cm), 'commit 面板双击选词保持原生行为')
call win_execute(s:cw,
            \ 'let b:vimb_release_map = maparg("<LeftRelease>", "v", 0, 1)')
let s:cr = getbufvar(winbufnr(s:cw), 'vimb_release_map', {})
call assert_true(get(s:cr, 'rhs', '') =~# 'CopyMouseSelection',
            \ 'commit 面板应有释放复制映射')
" commit 面板标题行首词是 vimb
call win_gotoid(s:cw)
call cursor(1, 2)
execute "normal! viw\<Esc>"
VimbCopyMouseSelection
call assert_equal('vimb', @", 'commit 面板应能复制标题中的 vimb')
call assert_equal('v', mode(), 'commit 面板复制后应保持选区高亮')
execute "normal! \<Esc>"

if executable('xclip') && $DISPLAY !=# ''
    sleep 100m
    let s:clipboard = join(systemlist('xclip -selection clipboard -out'), "\n")
    call assert_equal('vimb', s:clipboard, 'xclip 系统剪贴板应能读回复制内容')
endif
VimbTestFinish
qall!
