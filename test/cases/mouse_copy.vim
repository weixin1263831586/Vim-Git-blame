" mouse_copy：源码、blame、commit 面板均安装双击选择复制映射。
let s:fw = VimbTestFileWin()
let s:bw = VimbTestBufWin('\[vimb-blame\]')

for s:w in [s:fw, s:bw]
    call win_execute(s:w, 'let b:vimb_double_map = maparg("<2-LeftMouse>", "n", 0, 1)')
    let s:m = getbufvar(winbufnr(s:w), 'vimb_double_map', {})
    call assert_true(get(s:m, 'rhs', '') =~# 'CopyVisualSelection',
                \ '源码和 blame 都应有双击复制映射')
endfor

" 不依赖真实终端鼠标坐标，验证双击处理复用的剪贴板写入路径。
VimbCopyText alpha
call assert_equal('alpha', @", '双击复制处理应写入 unnamed register')

call VimbTestKey(s:fw, "\<CR>")
VimbWait
let s:cw = VimbTestBufWin('\[vimb-commit\]')
call assert_notequal(0, s:cw, '应打开 commit 面板')
call win_execute(s:cw, 'let b:vimb_double_map = maparg("<2-LeftMouse>", "n", 0, 1)')
let s:cm = getbufvar(winbufnr(s:cw), 'vimb_double_map', {})
call assert_true(get(s:cm, 'rhs', '') =~# 'CopyVisualSelection',
            \ 'commit 面板应有双击复制映射')
VimbTestFinish
qall!
