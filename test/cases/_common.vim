" vimb 测试公共助手：由 run.sh 通过 -c so 依次加载 _common.vim 和用例脚本。
" 断言用 assert_*()，失败信息累积在 v:errors，收尾写结果文件。

function! VimbTestFinish() abort
    let l:lines = empty(v:errors) ? ['PASS'] : ['FAIL'] + copy(v:errors)
    call writefile(l:lines, $VIMB_TEST_OUT)
endfunction
command! -bar VimbTestFinish call VimbTestFinish()

" 按缓冲区名字取窗口 id（找不到返回 0）
function! VimbTestBufWin(pattern) abort
    let l:b = bufnr(a:pattern)
    return l:b == -1 ? 0 : bufwinid(l:b)
endfunction

" 找 vimb 的源文件窗口：非 blame/commit 的窗口（栈层时显示 [vimb-src] 缓冲区）
function! VimbTestFileWin() abort
    for l:info in getwininfo()
        if l:info.tabnr != tabpagenr()
            continue
        endif
        let l:name = bufname(l:info.bufnr)
        if l:name =~# '\[vimb-blame\]'
        \ || l:name =~# '\[vimb-commit\]'
            continue
        endif
        return l:info.winid
    endfor
    return 0
endfunction

function! VimbTestRecords() abort
    return getbufvar(bufnr('\[vimb-blame\]'), 'vimb_records', [])
endfunction

function! VimbTestBlameBufnr() abort
    return bufnr('\[vimb-blame\]')
endfunction

function! VimbTestCommitBufnr() abort
    return bufnr('\[vimb-commit\]')
endfunction

" 按行号取源窗口当前行（直接解析 getpos，避免跨上下文变量问题）
function! VimbTestFileLine() abort
    let l:fw = VimbTestFileWin()
    if !l:fw
        return -1
    endif
    call win_execute(l:fw, 'let b:vimb_tpos = getpos(".")')
    return getbufvar(winbufnr(l:fw), 'vimb_tpos', [0, -1, 1, 0])[1]
endfunction

" 在指定窗口触发按键（feedkeys 而非 :normal——后者对纯空白键如 <Tab> 报 E471）
function! VimbTestKey(winid, keys) abort
    call win_execute(a:winid, 'call feedkeys("' . a:keys . '", "xt")')
endfunction

" 所有用例入口：先等后台 blame 加载完成（VIMB_SYNC=1 时立即返回）
VimbWait

