function! s:PopulatePendingBlame() abort
    call s:PopulateBlame(s:pending_records)
endfunction

function! s:ResizeBlame() abort
    let l:max_width = 24
    for l:text in getline(1, '$')
        let l:max_width = max([l:max_width, strdisplaywidth(l:text) + 1])
    endfor
    let l:limit = min([64, max([20, &columns / 2])])
    setlocal nowinfixwidth
    execute 'vertical resize ' . min([l:max_width, l:limit])
    setlocal winfixwidth
endfunction

function! s:CurrentRecord() abort
    if !exists('b:vimb_records')
        return {}
    endif
    return get(b:vimb_records, line('.') - 1, {})
endfunction

" 当前层当前行的 record（源窗口行号 = blame 行号）
function! s:CurrentLayerRecord() abort
    let l:records = empty(s:stack) ? [] : s:stack[-1].records
    let l:line = line('.')
    if win_getid() != s:SourceWin()
        let l:line = s:FileLine()
    endif
    return get(l:records, l:line - 1, {})
endfunction

function! s:HighlightCommit() abort
    for l:id in get(w:, 'vimb_match_ids', [])
        silent! call matchdelete(l:id)
    endfor
    let w:vimb_match_ids = []
    let l:record = s:CurrentRecord()
    if empty(l:record)
        return
    endif
    let l:positions = map(copy(get(b:vimb_hash_lines, l:record.hash, [])), '[v:val]')
    " 同 commit 色块优先级 10，会盖过 cursorline(优先级 2)；
    " 所在行再用优先级 20 叠加更醒目的高亮，避免淹没在色块中。
    if !empty(l:positions)
        call add(w:vimb_match_ids, matchaddpos('VimbSameCommit', l:positions, 10))
    endif
    call add(w:vimb_match_ids, matchaddpos('VimbCurrentLine', [line('.')], 20))
endfunction

function! s:FileLine() abort
    let l:fw = s:SourceWin()
    if !l:fw
        return 1
    endif
    let s:captured_line = 1
    call win_execute(l:fw, 'let s:captured_line = line(".")')
    return s:captured_line
endfunction

function! s:ClipDisplayText(text, width) abort
    let l:result = ''
    for l:char in split(a:text, '\zs')
        if strdisplaywidth(l:result . l:char . '…') > a:width
            return l:result . '…'
        endif
        let l:result .= l:char
    endfor
    return l:result
endfunction

" current-line compact 模式：源窗口状态栏常驻当前行 commit 摘要
function! s:UpdateCompactStatusline() abort
    let l:sw = s:SourceWin()
    if !l:sw
        return
    endif
    let l:record = get(empty(s:stack) ? [] : s:stack[-1].records,
                \ s:FileLine() - 1, {})
    let l:info = ''
    if !empty(l:record)
        if l:record.hash =~# '^0\+$'
            let l:info = 'WORKTREE（未提交）'
        else
            let l:info = strpart(l:record.hash, 0, 10)
                        \ . '  ' . get(l:record, 'author', '?')
            if get(l:record, 'author_time', 0) > 0
                let l:info .= '  ' . strftime('%Y-%m-%d', l:record.author_time)
            endif
            let l:summary = substitute(get(l:record, 'summary', ''),
                        \ '\s\+', ' ', 'g')
            let l:info .= '  ' . s:ClipDisplayText(l:summary, 60)
        endif
    endif
    call win_execute(l:sw, 'let &l:statusline = ' . string(' vimb  ' . l:info))
endfunction

function! s:FileCursorMoved() abort
    if s:syncing || s:refreshing || win_getid() != s:SourceWin()
        return
    endif
    let l:bw = s:BlameWin()
    if !l:bw
        return
    endif
    let s:syncing = 1
    try
        let l:target = line('.')
        call win_execute(l:bw,
                    \ 'call cursor(min([' . l:target . ', line("$")]), 1)')
        call win_execute(l:bw, 'VimbHighlightCommit')
        call s:UpdateCompactStatusline()
        if s:CommitWin()
            let s:return_view = winsaveview()
        endif
    finally
        let s:syncing = 0
    endtry
endfunction

function! s:BlameCursorMoved() abort
    if s:syncing || s:refreshing || win_getid() != s:BlameWin()
        return
    endif
    let l:fw = s:SourceWin()
    if !l:fw
        return
    endif
    let s:syncing = 1
    try
        let l:target = line('.')
        call win_execute(l:fw, 'call cursor(' . l:target . ', col("."))')
        call s:HighlightCommit()
        call s:UpdateCompactStatusline()
    finally
        let s:syncing = 0
    endtry
endfunction

function! s:SaveFileMap(lhs) abort
    let l:mapping = maparg(a:lhs, 'n', 0, 1)
    let s:file_maps[a:lhs] = !empty(l:mapping) && get(l:mapping, 'buffer', 0)
                \ ? l:mapping : {}
endfunction

function! s:InstallActiveFileMaps() abort
    let s:file_maps = {}
    for l:lhs in ['<F5>', '<CR>', '<Tab>', '<BS>', 'i', 'y', 'o',
                \ 'gh', 'gl', '<2-LeftMouse>']
        call s:SaveFileMap(l:lhs)
    endfor
    nnoremap <buffer> <silent> <F5> :call <SID>Refresh(1)<CR>
    nnoremap <buffer> <silent> <CR> :call <SID>ShowCommitAtFileLine()<CR>
    nnoremap <buffer> <silent> <Tab> :call <SID>PushOlder()<CR>
    nnoremap <buffer> <silent> <BS> :call <SID>PopNewer()<CR>
    nnoremap <buffer> <silent> i :call <SID>CommitInfo()<CR>
    nnoremap <buffer> <silent> y :call <SID>YankHash()<CR>
    nnoremap <buffer> <silent> o :call <SID>OpenInBrowser()<CR>
    nnoremap <buffer> <silent> gh :call <SID>ShowFileHistory()<CR>
    nnoremap <buffer> <silent> gl :call <SID>ShowLineHistory()<CR>
    nnoremap <buffer> <silent> <2-LeftMouse> :call <SID>CancelMouseClick()<CR><2-LeftMouse>:<C-U>call <SID>CopyVisualSelection()<CR>gv
endfunction

function! s:RestoreActiveFileMapsHere() abort
    for l:lhs in ['<F5>', '<CR>', '<Tab>', '<BS>', 'i', 'y', 'o',
                \ 'gh', 'gl', '<2-LeftMouse>']
        execute 'silent! nunmap <buffer> ' . l:lhs
        let l:mapping = get(s:file_maps, l:lhs, {})
        if !empty(l:mapping)
            call mapset('n', 0, l:mapping)
        endif
    endfor
    let s:file_maps = {}
endfunction

function! s:ActivateFile() abort
    let s:file_options = {'wrap': &l:wrap, 'scrollbind': &l:scrollbind,
                \ 'statusline': &l:statusline}
    setlocal nowrap
    setlocal noscrollbind
    call s:InstallActiveFileMaps()
    augroup VimbWorkspace
        autocmd! * <buffer>
        autocmd CursorMoved <buffer> call <SID>FileCursorMoved()
        autocmd BufWritePost <buffer> call <SID>Refresh(0)
        autocmd BufWipeout <buffer> call <SID>SourceGone()
    augroup END
endfunction

function! s:DeactivateFile() abort
    let l:fw = s:SourceWin()
    execute 'autocmd! VimbWorkspace * <buffer=' . s:file_bufnr . '>'
    if l:fw
        let l:wrap = get(s:file_options, 'wrap', 0)
        let l:scrollbind = get(s:file_options, 'scrollbind', 0)
        let l:statusline = get(s:file_options, 'statusline', '')
        call win_execute(l:fw, 'let &l:wrap = ' . l:wrap
                    \ . ' | let &l:scrollbind = ' . l:scrollbind)
        call win_execute(l:fw, 'let &l:statusline = ' . string(l:statusline))
        call win_execute(l:fw, 'VimbRestoreFileMaps')
    endif
    let s:file_options = {}
endfunction

function! s:ConfigureBlameBuffer() abort
    setlocal buftype=nofile
    setlocal bufhidden=wipe
    setlocal nobuflisted
    setlocal noswapfile
    setlocal nomodeline
    setlocal nowrap
    setlocal nonumber norelativenumber
    setlocal cursorline
    setlocal foldcolumn=0
    setlocal nofoldenable
    setlocal nospell
    setlocal undolevels=-1
    setlocal noscrollbind
    let &l:statusline = ' vimb blame  |  click/Enter: commit  |  q: close '
    silent execute 'file ' . fnameescape('[vimb-blame]')

    " 单击要等双击判定窗口结束再打开 commit；否则第一次 release 就改变
    " 布局，第二次点击既无法构成双击，也无法选择/复制 blame 文本。
    nnoremap <buffer> <silent> <LeftRelease> :call <SID>ScheduleMouseClick()<CR>
    nnoremap <buffer> <silent> <2-LeftMouse> :call <SID>CancelMouseClick()<CR><2-LeftMouse>:<C-U>call <SID>CopyVisualSelection()<CR>gv
    nnoremap <buffer> <silent> <CR> :call <SID>ShowCommit()<CR>
    nnoremap <buffer> <silent> <Tab> :call <SID>PushOlder()<CR>
    nnoremap <buffer> <silent> <BS> :call <SID>PopNewer()<CR>
    nnoremap <buffer> <silent> i :call <SID>CommitInfo()<CR>
    nnoremap <buffer> <silent> y :call <SID>YankHash()<CR>
    nnoremap <buffer> <silent> o :call <SID>OpenInBrowser()<CR>
    nnoremap <buffer> <silent> gh :call <SID>ShowFileHistory()<CR>
    nnoremap <buffer> <silent> gl :call <SID>ShowLineHistory()<CR>
    nnoremap <buffer> <silent> r :call <SID>Refresh(1)<CR>
    nnoremap <buffer> <silent> <F5> :call <SID>Refresh(1)<CR>
    nnoremap <buffer> <silent> q :call <SID>CloseBlame()<CR>
    nnoremap <buffer> <silent> <C-c> :call <SID>CloseBlame()<CR>
    nnoremap <buffer> <silent> gb :call <SID>CloseBlame()<CR>
    nnoremap <buffer> <silent> ? :call <SID>Help()<CR>

    augroup VimbWorkspace
        autocmd! * <buffer>
        autocmd WinEnter <buffer> call <SID>AuxFocusWithoutSource()
        autocmd CursorMoved <buffer> call <SID>BlameCursorMoved()
        autocmd BufWipeout <buffer> call <SID>BlameGone()
    augroup END
endfunction

function! s:ConfigureCommitBuffer() abort
    setlocal buftype=nofile
    setlocal bufhidden=wipe
    setlocal nobuflisted
    setlocal noswapfile
    setlocal nomodeline
    setlocal nowrap
    setlocal nonumber norelativenumber
    setlocal foldcolumn=0
    setlocal nofoldenable
    setlocal nospell
    setlocal undolevels=-1
    setlocal noscrollbind
    setlocal filetype=diff
    let &l:statusline = ' vimb commit  |  f: 仅此文件/全部文件  |  q/Backspace/Ctrl-O: return to source '
    silent execute 'file ' . fnameescape('[vimb-commit]')

    nnoremap <buffer> <silent> q :call <SID>CloseCommit(1)<CR>
    nnoremap <buffer> <silent> <C-c> :call <SID>CloseCommit(1)<CR>
    nnoremap <buffer> <silent> <BS> :call <SID>CloseCommit(1)<CR>
    nnoremap <buffer> <silent> <C-o> :call <SID>CloseCommit(1)<CR>
    nnoremap <buffer> <silent> f :call <SID>ToggleCommitScope()<CR>
    nnoremap <buffer> <silent> i :call <SID>CommitInfo()<CR>
    nnoremap <buffer> <silent> y :call <SID>YankHash()<CR>
    nnoremap <buffer> <silent> o :call <SID>OpenInBrowser()<CR>
    nnoremap <buffer> <silent> gb :call <SID>CloseBlame()<CR>
    nnoremap <buffer> <silent> ? :call <SID>Help()<CR>
    nnoremap <buffer> <silent> <2-LeftMouse> :call <SID>CancelMouseClick()<CR><2-LeftMouse>:<C-U>call <SID>CopyVisualSelection()<CR>gv

    augroup VimbWorkspace
        autocmd! * <buffer>
        autocmd WinEnter <buffer> call <SID>AuxFocusWithoutSource()
        autocmd BufWipeout <buffer> call <SID>CommitGone()
    augroup END
endfunction
