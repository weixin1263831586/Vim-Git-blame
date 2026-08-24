function! s:RenderCommit(record, file_only) abort
    let l:path = s:RecordPath(a:record)
    let b:vimb_hash = a:record.hash
    let b:vimb_file_only = a:file_only
    let b:vimb_summary = get(a:record, 'summary', '')
    let b:vimb_path = l:path
    let l:scope = a:file_only ? '仅此文件' : '全部文件'
    let l:title = 'vimb commit ' . a:record.hash . '  [' . l:scope . ']'
                \ . '  f: 切换范围  q/Backspace/Ctrl-O: 返回 '
                \ . l:path
    let l:rule = repeat('-', min([100, max([40, &columns - 1])]))
    " 窗口先就位并显示占位内容，Git 结果就绪后再填充
    call s:ReplaceCurrentBuffer([l:title, l:rule, '', '(正在加载 commit …)'])
    normal! gg
    let s:commit_gen += 1
    call s:CancelGitJobs('commit')
    let l:gen = s:commit_gen
    let l:cw = win_getid()
    call s:LoadCommitLines(a:record.hash, a:file_only, l:path,
                \ {ok, lines -> s:CommitRendered(ok, lines, l:gen, l:cw,
                \     l:title, l:rule, get(a:record, 'summary', ''))})
    return 1
endfunction

function! s:CommitRendered(ok, lines, gen, cw, title, rule, summary) abort
    if a:gen != s:commit_gen || !s:WindowMatches(a:cw, s:commit_bufnr)
        return
    endif
    if !a:ok
        call s:Error(s:GitFailure(a:lines))
        call win_execute(a:cw,
                    \ 'call s:ReplaceCurrentBuffer(["(加载 commit 失败)"])')
        return
    endif
    let l:content = [a:title, a:rule, ''] + a:lines
    call win_execute(a:cw,
                \ 'call s:ReplaceCurrentBuffer(' . string(l:content) . ')')
    call win_execute(a:cw, 'normal! gg')
    call s:Info(strpart(getbufvar(winbufnr(a:cw), 'vimb_hash'), 0, 12) . '  '
                \ . (empty(a:summary) ? getbufvar(winbufnr(a:cw), 'vimb_summary', '') : a:summary))
endfunction

function! s:OpenCommitForRecord(record) abort
    if a:record.hash =~# '^0\+$'
        call s:Error('这是尚未提交的工作区内容，没有可显示的 commit')
        return
    endif

    let l:fw = s:SourceWin()
    let l:bw = s:BlameWin()
    if !l:fw || !l:bw
        call s:Error('vimb 窗口状态已失效')
        return
    endif
    let s:return_view = s:CaptureView(l:fw)
    let l:file_view = copy(s:return_view)
    let l:blame_view = s:CaptureView(l:bw)
    let l:cw = s:CommitWin()

    if !l:cw
        call s:CloseHistory()
        noautocmd botright new
        let s:commit_winid = win_getid()
        let s:commit_bufnr = bufnr('%')
        call s:ConfigureCommitBuffer()
        execute 'resize ' . max([8, &lines * 2 / 5])
        setlocal winfixheight
        call s:RestoreView(l:fw, l:file_view)
        call s:RestoreView(l:bw, l:blame_view)
    else
        call win_gotoid(l:cw)
    endif

    " 同一个 commit + 历史路径重复打开时保留查看范围；路径不同也必须重置，
    " 否则 rename 两侧的同一提交会复用错误的文件范围。
    let l:path = s:RecordPath(a:record)
    let l:file_only = (get(b:, 'vimb_hash', '') ==# a:record.hash
                \ && get(b:, 'vimb_path', '') ==# l:path)
                \ ? get(b:, 'vimb_file_only', 1) : 1
    call s:RenderCommit(a:record, l:file_only)
endfunction

function! s:ShowCommit() abort
    if win_getid() != s:BlameWin()
        return
    endif
    let l:record = s:CurrentRecord()
    if empty(l:record)
        call s:Error('当前行没有 blame 信息')
        return
    endif
    call s:OpenCommitForRecord(l:record)
endfunction

function! s:ShowCommitAtFileLine() abort
    if win_getid() != s:SourceWin()
        return
    endif
    if !s:BlameWin()
        call s:OpenBlame()
        if !s:BlameWin()
            return
        endif
    endif
    let l:records = empty(s:stack) ? [] : s:stack[-1].records
    let l:record = get(l:records, line('.') - 1, {})
    if empty(l:record)
        call s:Error('当前行没有 blame 信息')
        return
    endif
    call s:OpenCommitForRecord(l:record)
endfunction

function! s:ToggleCommitScope() abort
    if win_getid() != s:CommitWin() || !exists('b:vimb_hash')
        return
    endif
    call s:RenderCommit({'hash': b:vimb_hash,
                \ 'summary': get(b:, 'vimb_summary', ''),
                \ 'path': get(b:, 'vimb_path', s:CurrentPath())},
                \ !get(b:, 'vimb_file_only', 1))
endfunction

function! s:CloseAuxWindow(winid) abort
    if !s:WindowMatches(a:winid, -1)
        return
    endif
    if win_getid() == a:winid
        silent! close!
    else
        call win_execute(a:winid, 'silent! close!')
    endif
endfunction

function! s:ReturnToFile() abort
    let l:fw = s:SourceWin()
    if !l:fw
        call s:Error('原文件窗口已经不存在')
        return
    endif
    call win_gotoid(l:fw)
    if !empty(s:return_view)
        call winrestview(s:return_view)
    endif
    if s:BlameWin()
        syncbind
    endif
endfunction

function! s:CloseCommit(return_to_file) abort
    let s:commit_gen += 1
    call s:CancelGitJobs('commit')
    let l:cw = s:CommitWin()
    if l:cw
        let s:closing_commit = 1
        try
            call s:CloseAuxWindow(l:cw)
        finally
            let s:closing_commit = 0
        endtry
    endif
    let s:commit_winid = -1
    let s:commit_bufnr = -1
    if a:return_to_file
        call s:ReturnToFile()
    endif
endfunction

function! s:CommitGone() abort
    let s:commit_winid = -1
    let s:commit_bufnr = -1
    if !s:closing_commit && !s:closing_blame
        call s:ReturnToFile()
    endif
endfunction
