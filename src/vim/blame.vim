function! s:BlameRequest(mode, notify) abort
    " mode: 'open' 首次打开 / 'refresh' 刷新 / 'push' 入栈 / 'pop' 出栈
    let s:blame_gen += 1
    call s:CancelDeferredBlameApply()
    call s:CancelGitJobs('blame')
    let l:gen = s:blame_gen
    let l:bw = s:blame_winid
    let l:fw = s:source_winid
    let l:layer = s:stack[-1]
    call s:GitLines(s:BlameCmd(l:layer.commit, l:layer.path),
                \ {ok, lines -> s:BlameLoaded(a:mode, a:notify, ok, lines,
                \     l:gen, l:bw, l:fw)}, 'blame')
endfunction

function! s:BlameLoaded(mode, notify, ok, lines, gen, bw, fw) abort
    if a:gen != s:blame_gen || !s:WindowMatches(a:bw, s:blame_bufnr)
        return
    endif
    if !a:ok || empty(s:stack)
        call s:Error(s:GitFailure(a:lines))
        if a:mode ==# 'open'
            call s:CloseBlame()
        elseif a:mode ==# 'push'
            call s:PopLayer(0)
        endif
        return
    endif
    let l:records = s:ParseBlameLines(a:lines)
    if !empty(a:lines) && empty(l:records)
        call s:Error('无法解析 git blame 输出')
        if a:mode ==# 'open'
            call s:CloseBlame()
        elseif a:mode ==# 'push'
            call s:PopLayer(0)
        endif
        return
    endif
    let s:stack[-1].records = l:records
    if s:stack[-1].commit ==# ''
        let s:stack[-1].mtime = getftime(s:file_path)
    endif
    call s:ApplyBlameRecords(a:bw, a:fw)
    call s:UpdateBlameStatusline()
    if a:mode ==# 'refresh' && a:notify
        call s:Info('blame 已刷新')
    endif
endfunction

" 用当前层记录填充 blame 窗口，并按源窗口行号对齐。
" 选区进行中（Visual/Select，含 :w 后立即双击的场景）必须延迟：填充/
" resize/对齐会改窗口宽度、移动光标、重设滚动，直接打断正在形成的选区。
function! s:ApplyBlameRecords(bw, fw) abort
    if s:SelectionActive() && s:WindowMatches(a:bw, s:blame_bufnr)
        call s:DeferBlameApply(a:bw, a:fw)
        return
    endif
    let s:refreshing = 1
    let s:pending_records = s:stack[-1].records
    try
        call win_execute(a:bw, 'VimbPopulatePendingBlame')
        call win_execute(a:bw, 'VimbResizeBlame')
        let l:line = s:FileLine()
        call win_execute(a:bw,
                    \ 'call cursor(min([' . l:line . ', line("$")]), 1)')
        call win_execute(a:bw, 'VimbHighlightCommit')
        if s:WindowMatches(a:fw, -1)
            call s:AlignBlameToSource()
        endif
        call s:UpdateCompactStatusline()
    finally
        let s:pending_records = []
        let s:refreshing = 0
    endtry
endfunction

" 延迟到回到 Normal 再应用；120ms 轮询直到选区自然结束。不设强制
" 应用的时限：长时间按住选区是合法状态（观察式复制依赖它），打断它
" 正是延迟应用要避免的问题；关闭 blame/窗口失配时定时器自会清理。
function! s:DeferBlameApply(bw, fw) abort
    call s:CancelDeferredBlameApply()
    if !exists('*timer_start')
        return
    endif
    let s:blame_apply_timer = timer_start(120,
                \ {timer -> s:BlameApplyTick(timer, a:bw, a:fw)},
                \ {'repeat': -1})
endfunction

function! s:BlameApplyTick(timer, bw, fw) abort
    if !s:active || !s:WindowMatches(a:bw, s:blame_bufnr)
        call s:CancelDeferredBlameApply()
        return
    endif
    if s:SelectionActive()
        return
    endif
    call s:CancelDeferredBlameApply()
    call s:ApplyBlameRecords(a:bw, a:fw)
endfunction

function! s:CancelDeferredBlameApply() abort
    if s:blame_apply_timer != -1 && exists('*timer_stop')
        call timer_stop(s:blame_apply_timer)
    endif
    let s:blame_apply_timer = -1
endfunction

function! s:OpenBlame() abort
    if s:active && s:BlameWin()
        return
    endif
    let l:fw = s:SourceWin()
    if !l:fw
        call s:Error('原文件窗口已经不存在，拒绝打开 blame')
        return
    endif
    call win_gotoid(l:fw)

    let l:file_view = winsaveview()
    try
        call s:ActivateFile()
        noautocmd leftabove vnew
        let s:blame_winid = win_getid()
        let s:blame_bufnr = bufnr('%')
        let s:active = 1
        call s:ConfigureBlameBuffer()
        call s:ReplaceCurrentBuffer(['(正在加载 blame …)'])

        setlocal scrollbind
        call win_execute(l:fw, 'setlocal scrollbind')
        call win_gotoid(l:fw)
        call winrestview(l:file_view)
        syncbind
        call s:BlameRequest('open', 0)
    catch
        let l:failure = v:exception
        call s:CloseBlame()
        call s:Error(l:failure)
    endtry
endfunction

function! s:Refresh(notify) abort
    let l:bw = s:BlameWin()
    let l:fw = s:SourceWin()
    if !l:bw || !l:fw
        if a:notify
            call s:Error('blame 当前未打开')
        endif
        return
    endif
    if len(s:stack) > 1
        if a:notify
            call s:Info('当前在历史层 ' . (len(s:stack) - 1)
                        \ . '，按 Backspace 退回工作区后再刷新')
        endif
        return
    endif
    call s:BlameRequest('refresh', a:notify)
endfunction
