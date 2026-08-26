function! s:BlameRequest(mode, notify) abort
    " mode: 'open' 首次打开 / 'refresh' 刷新 / 'push' 入栈 / 'pop' 出栈
    let s:blame_gen += 1
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

" 用当前层记录填充 blame 窗口，并按源窗口行号对齐
function! s:ApplyBlameRecords(bw, fw) abort
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
