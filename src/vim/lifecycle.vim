function! s:CloseBlame() abort
    call s:CancelMouseClick()
    call s:CancelGitJobs('blame')
    call s:InvalidateTrace()
    let l:fw = s:SourceWin()
    " 先清历史栈把源窗口切回真实文件，再按真实文件视图恢复
    if len(s:stack) > 1
        call s:ClearStack()
    endif
    let l:file_view = l:fw ? s:CaptureView(l:fw) : {}
    let s:closing_blame = 1
    try
        call s:CloseCommit(0)
        call s:CloseHistory()
        let l:bw = s:BlameWin()
        if l:bw
            call s:CloseAuxWindow(l:bw)
        endif
        let s:blame_winid = -1
        let s:blame_bufnr = -1
        let s:active = 0
        call s:DeactivateFile()
    finally
        let s:closing_blame = 0
    endtry
    if l:fw && s:WindowMatches(l:fw, s:file_bufnr)
        call win_gotoid(l:fw)
        call winrestview(l:file_view)
    endif
    echo ''
endfunction

function! s:BlameGone() abort
    call s:CancelGitJobs('blame')
    call s:InvalidateTrace()
    let s:blame_winid = -1
    let s:blame_bufnr = -1
    let s:active = 0
    if s:closing_blame
        return
    endif
    let l:fw = s:SourceWin()
    if len(s:stack) > 1
        call s:ClearStack()
    endif
    let l:view = l:fw ? s:CaptureView(l:fw) : {}
    let s:closing_blame = 1
    try
        call s:CloseCommit(0)
        call s:CloseHistory()
        call s:DeactivateFile()
    finally
        let s:closing_blame = 0
    endtry
    if l:fw
        call win_gotoid(l:fw)
        call winrestview(l:view)
    endif
endfunction

function! s:SourceGone() abort
    call s:CancelGitJobs('')
    call s:InvalidateTrace()
    let s:closing_blame = 1
    try
        call s:CloseCommit(0)
        call s:CloseHistory()
        call s:CloseAuxWindow(s:BlameWin())
    finally
        let s:closing_blame = 0
    endtry
    let s:active = 0
    let s:source_winid = -1
    let s:stack = [{'commit': '', 'path': s:rel_path, 'bufnr': s:file_bufnr,
                \ 'records': [], 'line': 1, 'mtime': -1}]
    let s:src_bufs = {}
    let s:src_cache_order = []
endfunction

function! s:AuxFocusWithoutSource() abort
    " 文件窗口被 :q / :wq / ZZ / <C-w>c 关闭后，焦点落入辅助面板时，
    " 面板已失去意义，直接退出，保证一次 :q 即可离开 vimb。
    if s:closing_blame || s:refreshing || s:SourceWin()
        return
    endif
    let s:closing_blame = 1
    try
        quit
    finally
        let s:closing_blame = 0
    endtry
endfunction

function! s:MouseClick() abort
    if exists('*getmousepos')
        let l:mouse = getmousepos()
        if get(l:mouse, 'winid', 0) == s:BlameWin() && get(l:mouse, 'line', 0) > 0
            call cursor(l:mouse.line, 1)
            call s:BlameCursorMoved()
            call s:ShowCommit()
        endif
    elseif win_getid() == s:BlameWin()
        call s:BlameCursorMoved()
        call s:ShowCommit()
    endif
endfunction

function! s:CancelMouseClick() abort
    if s:mouse_click_timer != -1 && exists('*timer_stop')
        call timer_stop(s:mouse_click_timer)
    endif
    let s:mouse_click_timer = -1
endfunction

function! s:RunMouseClick(timer, winid, line) abort
    let s:mouse_click_timer = -1
    if a:winid != s:BlameWin() || a:line <= 0
        return
    endif
    " 单击只在窗口始终停留在 Normal 模式时才生效：双击的第二击、拖拽都会
    " 进入 Visual。定时器触发时若已不在 Normal，说明那次按下演变成了
    " 双击/拖拽，放弃打开 commit 面板（不能在鼠标事件中途用 autocmd 干预，
    " 会破坏 Vim 内部的多击判定状态机）。
    if mode() !~# '^n'
        return
    endif
    call win_gotoid(a:winid)
    call cursor(a:line, 1)
    call s:BlameCursorMoved()
    call s:ShowCommit()
endfunction

function! s:ScheduleMouseClick() abort
    call s:CancelMouseClick()
    if !exists('*getmousepos') || !exists('*timer_start')
        call s:MouseClick()
        return
    endif
    let l:mouse = getmousepos()
    if get(l:mouse, 'winid', 0) != s:BlameWin() || get(l:mouse, 'line', 0) <= 0
        return
    endif
    " 比 'mousetime' 多留一个很小的调度余量；双击的第二击/拖拽会先进入
    " Visual 模式，RunMouseClick 的 mode() 校验会放弃过期单击。
    let s:mouse_click_timer = timer_start(&mousetime + 25,
                \ {timer -> s:RunMouseClick(timer, l:mouse.winid, l:mouse.line)})
endfunction

function! s:Toggle() abort
    if s:active || s:BlameWin()
        call s:CloseBlame()
    else
        call s:OpenBlame()
    endif
endfunction
