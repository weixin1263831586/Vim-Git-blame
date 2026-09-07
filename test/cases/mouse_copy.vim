" mouse_copy：原生鼠标选择 + 观察式自动复制。
" 所有鼠标事件（含双击/三击/四击与全部 release）必须保持 Vim 原生行为；
" 复制由全局观察器在选区稳定后触发，读取选区不打断进行中的 Visual
" （进行中不打断的行为由 pty e2e 的实时范围断言覆盖）。
let s:fw = VimbTestFileWin()
let s:bw = VimbTestBufWin('\[vimb-blame\]')

for s:w in [s:fw, s:bw]
    " Visual 模式的所有 release 事件不得被映射（保持原生选区生命周期）
    for s:ev in ['<LeftRelease>', '<2-LeftRelease>', '<3-LeftRelease>',
                \ '<4-LeftRelease>']
        call win_execute(s:w,
                    \ 'let b:vimb_release_map = maparg("' . s:ev . '", "v", 0, 1)')
        let s:release = getbufvar(winbufnr(s:w), 'vimb_release_map', {})
        call assert_true(empty(s:release),
                    \ '源码和 blame 不得映射 ' . s:ev . '（Visual 原生行为）')
    endfor
endfor
" 源码窗口连 Normal 模式 release 也不映射（blame 保留单击打开 commit）
call win_execute(s:fw,
            \ 'let b:vimb_release_n = maparg("<LeftRelease>", "n", 0, 1)')
call assert_true(empty(getbufvar(winbufnr(s:fw), 'vimb_release_n', {})),
            \ '源码窗口不得映射 <LeftRelease>')

" 纯函数选区读取（退出选区后经 '< '> 与 visualmode() 回退读取，同一选区）
call win_gotoid(s:fw)
call cursor(1, 7)
execute "normal! v"
call cursor(2, 4)
execute "normal! \<Esc>"
VimbVisualText
call assert_equal("one\nbeta", g:vimb_visual_text, '字符选区应等价 yank 结果')

" 行-wise
call cursor(1, 3)
execute "normal! Vj\<Esc>"
VimbVisualText
call assert_equal(join(getline(1, 2), "\n") . "\n",
            \ g:vimb_visual_text, '行选区应带尾部换行')

" 列块（\<C-v>）
call cursor(1, 3)
execute "normal! \<C-v>jl\<Esc>"
VimbVisualText
call assert_equal("ph\nta", g:vimb_visual_text, '列块选区逐行按列切片')

" 多字节安全：选区止于多字节字符首字节时包含完整字符
let s:saved_line3 = getline(3)
call setline(3, '中文字符测试')
call cursor(3, 1)
execute "normal! v4l\<Esc>"
VimbVisualText
call assert_equal('中文字符测', g:vimb_visual_text, '多字节选区按字符边界切片')
call setline(3, s:saved_line3)

" 和 Vim 自身的 yank 对照，而不是重复实现选区算法。
let s:saved_lines = getline(1, '$')
let s:saved_selection = &selection
let s:saved_ve = &virtualedit
let s:saved_ts = &tabstop
set tabstop=8 virtualedit=
call setline(1, ['a\tbcd', '0123456789', '中文字符', '', 'ábc'])
" 第一行要包含真实 Tab。
call setline(1, "a\tbcd")
xnoremap <buffer> <F12> <Cmd>VimbVisualText<CR>
for s:selection in ['inclusive', 'exclusive', 'old']
    let &selection = s:selection
    for s:keys in ["gg0v3l", "gg03lv3h", "gg0vj0", "gg0v$",
                \ "gg0\<C-v>jl", "gg0l\<C-v>j3l", "3G0v2l",
                \ "3G0\<C-v>k2l", "4G0v", "5G0vl", "gg0\<C-v>j$",
                \ "2G03l\<C-v>k0"]
        call feedkeys(s:keys . "\<F12>\<Esc>", 'xt')
        let s:actual = g:vimb_visual_text
        normal! gvy
        call assert_equal(@", s:actual,
                    \ '选区必须与原生 yank 一致: ' . s:selection . ' ' . strtrans(s:keys))
    endfor
endfor
set virtualedit=block selection=inclusive
for s:keys in ["gg0l\<C-v>j2l", "3G0\<C-v>j5l", "gg0\<C-v>j$",
            \ "gg0\<C-v>j12l"]
    call feedkeys(s:keys . "\<F12>\<Esc>", 'xt')
    let s:actual = g:vimb_visual_text
    normal! gvy
    call assert_equal(@", s:actual, 'virtual block: ' . strtrans(s:keys))
endfor
xunmap <buffer> <F12>
let &selection = s:saved_selection
let &virtualedit = s:saved_ve
let &tabstop = s:saved_ts
call setline(1, s:saved_lines)

" 观察式复制核心：选区稳定后复制（刚结束的选区经 marks 回退同样可复制）
call cursor(1, 3)
execute "normal! viw\<Esc>"
VimbVisualCopyNow
call assert_equal('alpha', @", '选区稳定后应自动复制 alpha')

call VimbTestKey(s:fw, "\<CR>")
VimbWait
let s:cw = VimbTestBufWin('\[vimb-commit\]')
call assert_notequal(0, s:cw, '应打开 commit 面板')
" commit 面板同样零鼠标映射；标题词 vimb 可观察式复制
call win_execute(s:cw,
            \ 'let b:vimb_cr = maparg("<2-LeftRelease>", "v", 0, 1)')
call assert_true(empty(getbufvar(winbufnr(s:cw), 'vimb_cr', {})),
            \ 'commit 面板不得映射 release（保持原生行为）')
call win_gotoid(s:cw)
call cursor(1, 2)
execute "normal! viw\<Esc>"
VimbVisualCopyNow
call assert_equal('vimb', @", 'commit 面板应能复制标题中的 vimb')

if executable('xclip') && $DISPLAY !=# ''
    sleep 100m
    let s:clipboard = join(systemlist('xclip -selection clipboard -out'), "\n")
    call assert_equal('vimb', s:clipboard, 'xclip 系统剪贴板应能读回复制内容')
endif
VimbTestFinish
qall!
