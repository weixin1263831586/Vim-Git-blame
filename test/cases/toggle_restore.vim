" toggle：关闭 blame 后 wrap / 用户 F5 映射完整恢复
setlocal wrap
nnoremap <buffer> <F5> :let g:user_f5_fired = 1<CR>

VimbToggle
call assert_notequal(0, VimbTestBufWin('\[vimb-blame\]'), 'VimbToggle 应打开 blame')
call assert_equal(0, &l:wrap, '打开 blame 时应设 nowrap')
let s:m = maparg('<F5>', 'n', 0, 1)
call assert_equal(1, get(s:m, 'buffer', 0), 'F5 应为缓冲区局部映射')
call assert_false(stridx(get(s:m, 'rhs', ''), 'user_f5_fired') >= 0,
            \ 'F5 应被 vimb 接管')

VimbToggle
call assert_equal(0, VimbTestBufWin('\[vimb-blame\]'), '再次 VimbToggle 应关闭 blame')
call assert_equal(1, &l:wrap, 'wrap 应恢复为 1')
let s:m2 = maparg('<F5>', 'n', 0, 1)
call assert_equal(':let g:user_f5_fired = 1<CR>', get(s:m2, 'rhs', ''),
            \ '用户 F5 映射应恢复')
call assert_equal(get(s:m, 'buffer', 0), get(s:m2, 'buffer', 0),
            \ '映射的缓冲区局部属性应与原映射一致')
VimbTestFinish
qall!
