" 缓存深度为 1：深追溯只保留当前源码 buffer，返回时应透明地懒加载。
let s:fw = VimbTestFileWin()
for s:expected in ['deep 2', 'deep 1', 'deep 0']
    call VimbTestKey(s:fw, '\<Tab>')
    VimbWait
    call assert_equal(s:expected,
                \ get(getbufline(winbufnr(s:fw), 1, 1), 0, ''),
                \ 'Tab 应进入上一历史版本')
endfor
let s:src_count = len(filter(getbufinfo(),
            \ 'bufname(v:val.bufnr) =~# "\\[vimb-src @"'))
call assert_true(s:src_count <= 1, '历史源码 buffer 数应受缓存深度限制')

for s:expected in ['deep 1', 'deep 2', 'deep 3']
    call VimbTestKey(s:fw, '\<BS>')
    VimbWait
    call assert_equal(s:expected,
                \ get(getbufline(winbufnr(s:fw), 1, 1), 0, ''),
                \ 'Backspace 应重新载入已淘汰的较新版本')
endfor
VimbTestFinish
qall!
