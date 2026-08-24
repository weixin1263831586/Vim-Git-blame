" ---- 历史面板：gh 文件历史 / gl 行历史 ------------------------------------
" 复用底部面板窗口（与 commit 面板互斥，谁后打开谁占位）
let s:history_winid = -1
let s:history_bufnr = -1
let s:history_gen = 0

function! s:ConfigureHistoryBuffer(kind) abort
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
    let b:vimb_history_kind = a:kind
    let &l:statusline = a:kind ==# 'file'
                \ ? ' vimb 文件历史  |  Enter: commit  Tab: 进入版本  y/o: SHA/浏览器  q: 关闭 '
                \ : ' vimb 行历史  |  Enter: commit  Tab: 进入版本  y/o: SHA/浏览器  q: 关闭 '
    silent execute 'file ' . fnameescape('[vimb-history]')

    nnoremap <buffer> <silent> q :call <SID>CloseHistory()<CR>
    nnoremap <buffer> <silent> <C-c> :call <SID>CloseHistory()<CR>
    nnoremap <buffer> <silent> gh :call <SID>ShowFileHistory()<CR>
    nnoremap <buffer> <silent> gl :call <SID>ShowLineHistory()<CR>
    nnoremap <buffer> <silent> <CR> :call <SID>OpenHistoryCommit()<CR>
    nnoremap <buffer> <silent> <Tab> :call <SID>EnterHistoryRevision()<CR>
    nnoremap <buffer> <silent> y :call <SID>YankHash()<CR>
    nnoremap <buffer> <silent> o :call <SID>OpenInBrowser()<CR>
    nnoremap <buffer> <silent> ? :call <SID>Help()<CR>

    augroup VimbWorkspace
        autocmd! * <buffer>
        autocmd WinEnter <buffer> call <SID>AuxFocusWithoutSource()
        autocmd BufWipeout <buffer> call <SID>HistoryGone()
    augroup END
endfunction

" 历史/commit 共用底部窗口：互斥打开
function! s:OpenBottomPanel(configure_fn) abort
    call s:CloseCommit(0)
    let s:history_winid = s:WindowForBuffer(s:history_winid, s:history_bufnr)
    if !s:history_winid
        noautocmd botright new
        let s:history_winid = win_getid()
        let s:history_bufnr = bufnr('%')
        execute 'resize ' . max([8, &lines * 2 / 5])
        setlocal winfixheight
    else
        call win_gotoid(s:history_winid)
    endif
    if s:history_bufnr != bufnr('%')
        " 窗口里换了缓冲区（commit 面板复用同窗口），重配
        let s:history_bufnr = bufnr('%')
    endif
    call call(a:configure_fn, [])
    return s:history_winid
endfunction

function! s:CloseHistory() abort
    " 主动失效在途回调，防止关闭后晚到的异步结果再写窗口
    let s:history_gen += 1
    if s:WindowMatches(s:history_winid, -1)
        if win_getid() == s:history_winid
            silent! close!
        else
            call win_execute(s:history_winid, 'silent! close!')
        endif
    endif
    let s:history_winid = -1
    let s:history_bufnr = -1
endfunction

function! s:HistoryGone() abort
    let s:history_gen += 1
    let s:history_winid = -1
    let s:history_bufnr = -1
endfunction

function! s:ShowFileHistory() abort
    let l:sw = s:SourceWin()
    if !l:sw
        return
    endif
    let l:path = empty(s:stack) ? s:rel_path : s:stack[-1].path
    let l:commit = empty(s:stack) ? '' : s:stack[-1].commit
    let l:title = 'vimb 文件历史  ' . l:path
    let l:rule = repeat('-', min([100, max([40, &columns - 1])]))
    let l:hw = s:OpenBottomPanel(
                \ {-> s:ConfigureHistoryBuffer('file')})
    call win_execute(l:hw, 'call s:ReplaceCurrentBuffer(["' . l:title . '", "' . l:rule . '", "", "(正在加载文件历史 …)"])')
    let s:history_gen += 1
    let l:gen = s:history_gen
    " --name-status 用 rename 状态维护每条历史记录当时的路径，Tab 才能
    " 直接进入 rename 前的 revision。format 串必须整体引号包裹。
    let l:cmd = s:GitBase()
                \ . " log --follow --name-status"
                \ . " --pretty=format:'COMMIT@%H|%h|%an|%ad|%s' --date=short"
    if l:commit !=# ''
        let l:cmd .= ' ' . shellescape(l:commit)
    endif
    let l:cmd .= ' -- ' . shellescape(l:path) . ' 2>&1'
    call s:GitLines(l:cmd,
                \ {ok, lines -> s:HistoryRendered('file', ok, lines, l:gen,
                \     l:hw, l:title, l:rule, l:path)})
endfunction

function! s:ShowLineHistory() abort
    let l:sw = s:SourceWin()
    if !l:sw
        return
    endif
    let l:path = empty(s:stack) ? s:rel_path : s:stack[-1].path
    let l:line = s:FileLine()
    let l:title = 'vimb 行历史  ' . l:path . '  第 ' . l:line . ' 行'
    let l:rule = repeat('-', min([100, max([40, &columns - 1])]))
    let l:hw = s:OpenBottomPanel(
                \ {-> s:ConfigureHistoryBuffer('line')})
    call win_execute(l:hw, 'call s:ReplaceCurrentBuffer(["' . l:title . '", "' . l:rule . '", "", "(正在加载行历史 …)"])')
    let s:history_gen += 1
    let l:gen = s:history_gen
    " 历史层从当前 revision 起算（HEAD 视角可能已不存在旧路径）
    let l:commit = empty(s:stack) ? '' : s:stack[-1].commit
    let l:cmd = s:GitBase()
                \ . ' log'
    if l:commit !=# ''
        let l:cmd .= ' ' . shellescape(l:commit)
    endif
    let l:cmd .= ' -L ' . l:line . ',' . l:line . ':'
                \ . shellescape(l:path)
                \ . " --pretty=format:'COMMIT@%H|%h|%an|%ad|%s'"
                \ . ' --date=short 2>&1'
    call s:GitLines(l:cmd,
                \ {ok, lines -> s:HistoryRendered('line', ok, lines, l:gen,
                \     l:hw, l:title, l:rule, l:path)})
endfunction

function! s:HistoryRendered(kind, ok, lines, gen, hw, title, rule, path) abort
    " 窗口可能已被用户关闭（异步回调晚到）：gen 与窗口双校验，
    " 任何一项不满足都直接丢弃，绝不向失效窗口写入
    if a:gen != s:history_gen || !s:WindowMatches(a:hw, s:history_bufnr)
        return
    endif
    if !a:ok
        call win_execute(a:hw,
                    \ 'call s:ReplaceCurrentBuffer(["(加载历史失败)"])')
        return
    endif
    let l:content = [a:title, a:rule, '']
    let l:records = [{}, {}, {}]
    if a:kind ==# 'file'
        let l:current_path = a:path
        for l:raw in a:lines
            if stridx(l:raw, 'COMMIT@') == 0
                let l:parts = split(strpart(l:raw, 7), '|', 1)
            else
                let l:parts = []
            endif
            if len(l:parts) >= 5
                let l:record = {'hash': l:parts[0], 'short_hash': l:parts[1],
                            \ 'author': l:parts[2], 'date': l:parts[3],
                            \ 'summary': join(l:parts[4:], '|'),
                            \ 'path': l:current_path}
                " 作者列按显示宽度填充，避免中文作者名错位
                call add(l:content, printf('%-10s ', l:record.short_hash)
                            \ . s:ClipAndPad(l:record.author, 12) . ' '
                            \ . l:record.date . '  ' . l:record.summary)
                call add(l:records, l:record)
            elseif l:raw =~# '^R\d*\t'
                let l:renamed = split(l:raw, "\t", 1)
                if len(l:renamed) >= 3 && l:renamed[2] ==# l:current_path
                    let l:current_path = l:renamed[1]
                endif
            endif
        endfor
    else
        " git log -L 输出交织 commit 头与 diff；commit 头转为可交互记录。
        for l:raw in a:lines
            if stridx(l:raw, 'COMMIT@') == 0
                let l:parts = split(strpart(l:raw, 7), '|', 1)
            else
                let l:parts = []
            endif
            if len(l:parts) >= 5
                let l:record = {'hash': l:parts[0], 'short_hash': l:parts[1],
                            \ 'author': l:parts[2], 'date': l:parts[3],
                            \ 'summary': join(l:parts[4:], '|'), 'path': a:path}
                call add(l:content, printf('%-10s ', l:record.short_hash)
                            \ . s:ClipAndPad(l:record.author, 12) . ' '
                            \ . l:record.date . '  ' . l:record.summary)
                call add(l:records, l:record)
            else
                call add(l:content, l:raw)
                call add(l:records, {})
            endif
        endfor
    endif
    call win_execute(a:hw,
                \ 'call s:ReplaceCurrentBuffer(' . string(l:content) . ')')
    call setbufvar(s:history_bufnr, 'vimb_history_records', l:records)
endfunction

function! s:CurrentHistoryRecord() abort
    if !s:WindowMatches(s:history_winid, s:history_bufnr)
                \ || win_getid() != s:history_winid
        return {}
    endif
    return get(get(b:, 'vimb_history_records', []), line('.') - 1, {})
endfunction

function! s:OpenHistoryCommit() abort
    let l:record = s:CurrentHistoryRecord()
    if empty(l:record)
        call s:Info('请将光标移到一条 commit 记录上')
        return
    endif
    call s:OpenCommitForRecord(l:record)
endfunction

function! s:EnterHistoryRevision() abort
    let l:record = s:CurrentHistoryRecord()
    if empty(l:record)
        call s:Info('请将光标移到一条 commit 记录上')
        return
    endif
    if s:trace_busy
        call s:Info('正在追溯，请稍候 …')
        return
    endif
    let l:cur_layer = s:stack[-1]
    if l:cur_layer.commit ==# l:record.hash && l:cur_layer.path ==# l:record.path
        call s:Info('已经位于所选 revision')
        return
    endif
    let l:target_line = s:FileLine()
    let s:trace_gen += 1
    let s:trace_busy = 1
    let l:gen = s:trace_gen
    let l:key = l:record.hash . ':' . l:record.path
    call s:CloseHistory()
    if has_key(s:src_bufs, l:key) && bufexists(s:src_bufs[l:key])
        call s:FinishPush(l:record.hash, l:record.path, s:src_bufs[l:key],
                    \ l:target_line, l:cur_layer, l:gen)
        return
    endif
    call s:Info('正在进入 ' . strpart(l:record.hash, 0, 10) . ' …')
    call s:GitShowFileAsync(l:record.hash, l:record.path,
                \ {ok, lines -> s:HistoryRevisionLoaded(ok, lines, l:record,
                \     l:target_line, l:cur_layer, l:gen)})
endfunction

function! s:HistoryRevisionLoaded(ok, lines, record, target_line, cur_layer, gen) abort
    if !s:TraceIsCurrent(a:gen, a:cur_layer)
        return
    endif
    if !a:ok
        call s:FinishTrace(a:gen)
        call s:Error('无法读取所选 revision 的文件内容')
        return
    endif
    let l:bufnr = s:CreateSrcBuffer(a:record.hash, a:record.path, a:lines)
    call s:FinishPush(a:record.hash, a:record.path, l:bufnr, a:target_line,
                \ a:cur_layer, a:gen)
endfunction
