" ---- blame 历史栈 ----------------------------------------------------------
" git line-log 会把目标 child 行窄化成它自己的 hunk，因此 mixed
" insertion+replacement 也能得到可靠的 parent 行；old_count=0 才表示
" 该逻辑行在 parent 中不存在。
function! s:MapLineLogToParent(log_lines, child_line) abort
    for l:raw in a:log_lines
        let l:m = matchlist(l:raw,
                    \ '^@@ -\(\d\+\)\%(,\(\d\+\)\)\? +\(\d\+\)\%(,\(\d\+\)\)\? @@')
        if !empty(l:m)
            let l:old_start = str2nr(l:m[1])
            let l:old_count = l:m[2] ==# '' ? 1 : str2nr(l:m[2])
            let l:new_start = str2nr(l:m[3])
            let l:new_count = l:m[4] ==# '' ? 1 : str2nr(l:m[4])
            if l:old_count == 0
                return -1
            endif
            " 通常 line-log 已收窄为 1→1；保留相对索引作为兼容兜底。
            let l:index = max([0, a:child_line - l:new_start])
            return l:old_start + min([l:index, l:old_count - 1])
        endif
    endfor
    return 0
endfunction

" 让 Git 自己追踪目标行，而不是用 whole-file diff hunk header 猜映射。
" 回调 on_done(ok, parent_line, lines)，parent_line=-1 表示首次引入。
" parent_line == -1 表示该行为本 commit 新增
function! s:ChildToParentLineAsync(child_commit, child_path, record, on_done) abort
    let l:child_line = get(a:record, 'original_line', 1)
    let l:range = l:child_line . ',' . l:child_line . ':' . a:child_path
    let l:cmd = s:GitBase()
                \ . ' log -1 --no-color --no-ext-diff --format= -L '
                \ . shellescape(l:range) . ' ' . shellescape(a:child_commit)
                \ . ' 2>&1'
    call s:GitLines(l:cmd, {ok, lines ->
                \ call(a:on_done, [ok,
                \     ok ? s:MapLineLogToParent(lines, l:child_line) : 0,
                \     lines])}, 'trace')
endfunction

" git show <commit>:<path> 异步读取文件内容；回调 on_done(ok, lines)
function! s:GitShowFileAsync(commit, path, on_done) abort
    let l:cmd = s:GitBase()
                \ . ' show ' . shellescape(a:commit . ':' . a:path) . ' 2>&1'
    call s:GitLines(l:cmd, a:on_done, 'trace')
endfunction

" 取历史版本缓冲区（懒创建并缓存）。同步读取已移除：内容由调用方经
" GitShowFileAsync 取得后经 CreateSrcBuffer 落地。
function! s:TouchSrcCache(key) abort
    let l:index = index(s:src_cache_order, a:key)
    if l:index >= 0
        call remove(s:src_cache_order, l:index)
    endif
    call add(s:src_cache_order, a:key)
endfunction

function! s:CachedSrcBuffer(key) abort
    if !has_key(s:src_bufs, a:key) || !bufexists(s:src_bufs[a:key])
        if has_key(s:src_bufs, a:key)
            call remove(s:src_bufs, a:key)
        endif
        let l:index = index(s:src_cache_order, a:key)
        if l:index >= 0
            call remove(s:src_cache_order, l:index)
        endif
        return -1
    endif
    call s:TouchSrcCache(a:key)
    return s:src_bufs[a:key]
endfunction

" 只淘汰当前未显示的历史层；stack 的 commit/path/line 元数据继续保留，
" 对应 records 一并释放，Backspace 返回时再异步 git show + blame。
function! s:PruneSrcCache() abort
    let l:current = empty(s:stack) ? -1 : s:stack[-1].bufnr
    while len(s:src_cache_order) > s:history_cache_depth
        let l:index = -1
        for l:i in range(0, len(s:src_cache_order) - 1)
            let l:key = s:src_cache_order[l:i]
            if get(s:src_bufs, l:key, -1) != l:current
                let l:index = l:i
                break
            endif
        endfor
        if l:index < 0
            break
        endif
        let l:key = remove(s:src_cache_order, l:index)
        if !has_key(s:src_bufs, l:key)
            continue
        endif
        let l:bufnr = remove(s:src_bufs, l:key)
        for l:layer in s:stack
            if l:layer.commit . ':' . l:layer.path ==# l:key
                let l:layer.bufnr = -1
                let l:layer.records = []
            endif
        endfor
        if bufexists(l:bufnr)
            execute 'silent! bwipeout ' . l:bufnr
        endif
    endwhile
endfunction

function! s:CreateSrcBuffer(commit, path, lines) abort
    let l:key = a:commit . ':' . a:path
    let l:cached = s:CachedSrcBuffer(l:key)
    if l:cached > 0
        return l:cached
    endif
    let l:bufnr = bufadd('[vimb-src @' . strpart(a:commit, 0, 10) . ' '
                \ . fnamemodify(a:path, ':t') . ']')
    call bufload(l:bufnr)
    " 去掉行尾 \r，与真实文件窗口的显示保持一致
    let l:lines = copy(a:lines)
    call map(l:lines, 'substitute(v:val, "\r$", "", "")')
    call setbufline(l:bufnr, 1, empty(l:lines) ? [''] : l:lines)
    call setbufvar(l:bufnr, '&buftype', 'nofile')
    call setbufvar(l:bufnr, '&bufhidden', 'hide')
    call setbufvar(l:bufnr, '&swapfile', 0)
    call setbufvar(l:bufnr, '&modifiable', 0)
    call setbufvar(l:bufnr, '&modified', 0)
    call setbufvar(l:bufnr, '&modeline', 0)
    call setbufvar(l:bufnr, '&undolevels', -1)
    if s:file_filetype !=# ''
        call setbufvar(l:bufnr, '&filetype', s:file_filetype)
    endif
    call setbufvar(l:bufnr, 'vimb_src', 1)
    let s:src_bufs[l:key] = l:bufnr
    call s:TouchSrcCache(l:key)
    return l:bufnr
endfunction

" 把栈层缓冲区显示到源窗口，并安装栈层专用映射
function! s:ShowLayerInSource(layer) abort
    let l:sw = s:SourceWin()
    if !l:sw
        return 0
    endif
    call win_execute(l:sw, 'noautocmd buffer ' . a:layer.bufnr)
    if !empty(a:layer.commit)
        " 栈内历史版本缓冲区：完整操作集（映射随缓冲区，只装一次）
        if !getbufvar(a:layer.bufnr, 'vimb_maps_done', 0)
            call win_execute(l:sw, 'nnoremap <buffer> <silent> <CR>'
                        \ . ' :call <SID>ShowCommitAtFileLine()<CR>')
            call win_execute(l:sw, 'nnoremap <buffer> <silent> <Tab>'
                        \ . ' :call <SID>PushOlder()<CR>')
            call win_execute(l:sw, 'nnoremap <buffer> <silent> <BS>'
                        \ . ' :call <SID>PopNewer()<CR>')
            call win_execute(l:sw, 'nnoremap <buffer> <silent> i'
                        \ . ' :call <SID>CommitInfo()<CR>')
            call win_execute(l:sw, 'nnoremap <buffer> <silent> y'
                        \ . ' :call <SID>YankHash()<CR>')
            call win_execute(l:sw, 'nnoremap <buffer> <silent> o'
                        \ . ' :call <SID>OpenInBrowser()<CR>')
            call win_execute(l:sw, 'nnoremap <buffer> <silent> gh'
                        \ . ' :call <SID>ShowFileHistory()<CR>')
            call win_execute(l:sw, 'nnoremap <buffer> <silent> gl'
                        \ . ' :call <SID>ShowLineHistory()<CR>')
            call win_execute(l:sw, 'nnoremap <buffer> <silent> gb'
                        \ . ' :call <SID>Toggle()<CR>')
            call win_execute(l:sw, 'nnoremap <buffer> <silent> ?'
                        \ . ' :call <SID>Help()<CR>')
            call setbufvar(a:layer.bufnr, 'vimb_maps_done', 1)
            augroup VimbWorkspace
                execute 'autocmd CursorMoved <buffer=' . a:layer.bufnr . '>'
                            \ . ' call <SID>FileCursorMoved()'
            augroup END
        endif
    endif
    return 1
endfunction

" Tab：把当前行追溯到引入它的父提交（入栈）
function! s:PushOlder() abort
    if empty(s:stack)
        return
    endif
    let l:record = s:CurrentLayerRecord()
    if empty(l:record)
        call s:Error('当前行没有 blame 信息')
        return
    endif
    if l:record.hash =~# '^0\+$'
        call s:Info('该行是未提交的工作区内容，先提交后才能追溯')
        return
    endif
    if get(l:record, 'previous', '') ==# ''
        call s:Info('该行已追溯到最早引入它的提交（boundary）')
        return
    endif
    if s:trace_busy
        call s:Info('正在追溯，请稍候 …')
        return
    endif
    let l:cur_layer = s:stack[-1]
    " original_line 属于 blame record.hash 的坐标系；child revision/path 必须
    " 与它一致，不能用栈顶 HEAD/commit（其后提交可能已在目标行前增删内容）。
    let l:child_commit = l:record.hash
    let l:child_path = get(l:record, 'filename', '')
    if l:child_path ==# ''
        let l:child_path = l:cur_layer.path
    endif
    let s:trace_gen += 1
    let s:trace_busy = 1
    let l:gen = s:trace_gen
    " 全异步链：diff hunk 映射 → 读取父版本内容 → 建缓冲区 → 入栈
    call s:ChildToParentLineAsync(l:child_commit, l:child_path, l:record,
                \ {ok, parent_line, diff_lines ->
                \     s:PushOlderAfterMap(ok, parent_line, l:record,
                \         l:cur_layer, l:gen)})
endfunction

function! s:TraceIsCurrent(gen, layer) abort
    return a:gen == s:trace_gen && s:trace_busy && s:active
                \ && s:BlameWin() && s:SourceWin() && !empty(s:stack)
                \ && s:stack[-1] is a:layer
endfunction

function! s:FinishTrace(gen) abort
    if a:gen == s:trace_gen
        let s:trace_busy = 0
    endif
endfunction

function! s:InvalidateTrace() abort
    let s:trace_gen += 1
    let s:trace_busy = 0
    call s:CancelGitJobs('trace')
endfunction

" diff 映射完成后：校验行号是否有效，再异步取父版本内容
function! s:PushOlderAfterMap(ok, parent_line, record, cur_layer, gen) abort
    if !s:TraceIsCurrent(a:gen, a:cur_layer)
        return
    endif
    if !a:ok
        call s:FinishTrace(a:gen)
        call s:Error('无法计算父版本行号（git diff 失败）')
        return
    endif
    if a:parent_line <= 0
        call s:FinishTrace(a:gen)
        call s:Info('该行在 commit ' . strpart(a:record.hash, 0, 10)
                    \ . ' 中首次引入，没有更早的来源')
        return
    endif
    let l:prev = a:record.previous
    let l:prev_path = get(a:record, 'previous_path', '')
    if l:prev_path ==# ''
        let l:prev_path = a:cur_layer.path
    endif
    " 已有缓存缓冲区可直接入栈；否则异步读取内容
    let l:key = l:prev . ':' . l:prev_path
    let l:cached = s:CachedSrcBuffer(l:key)
    if l:cached > 0
        call s:FinishPush(l:prev, l:prev_path, l:cached,
                    \ a:parent_line, a:cur_layer, a:gen)
        return
    endif
    call s:Info('正在追溯 ' . strpart(l:prev, 0, 10) . ' …')
    call s:GitShowFileAsync(l:prev, l:prev_path,
                \ {ok, lines -> s:PushOlderAfterShow(ok, lines, l:prev,
                \     l:prev_path, a:parent_line, a:cur_layer, a:gen)})
endfunction

function! s:PushOlderAfterShow(ok, lines, prev, prev_path, parent_line, cur_layer, gen) abort
    if !s:TraceIsCurrent(a:gen, a:cur_layer)
        return
    endif
    if !a:ok
        call s:FinishTrace(a:gen)
        call s:Error('无法读取 ' . strpart(a:prev, 0, 10) . ' 版本的文件内容')
        return
    endif
    let l:bufnr = s:CreateSrcBuffer(a:prev, a:prev_path, a:lines)
    call s:FinishPush(a:prev, a:prev_path, l:bufnr, a:parent_line,
                \ a:cur_layer, a:gen)
endfunction

function! s:FinishPush(prev, prev_path, bufnr, parent_line, cur_layer, gen) abort
    if !s:TraceIsCurrent(a:gen, a:cur_layer)
        return
    endif
    " 记录当前层光标行，出栈时恢复
    let s:stack[-1].line = s:FileLine()
    call add(s:stack, {'commit': a:prev, 'path': a:prev_path,
                \ 'bufnr': a:bufnr, 'records': [], 'line': a:parent_line,
                \ 'mtime': -1})
    let l:layer = s:stack[-1]
    let l:sw = s:SourceWin()
    if !l:sw || !s:ShowLayerInSource(l:layer)
        call remove(s:stack, -1)
        call s:FinishTrace(a:gen)
        call s:Error('源窗口已不存在，无法入栈')
        return
    endif
    call s:TouchSrcCache(a:prev . ':' . a:prev_path)
    call s:PruneSrcCache()
    let l:count = len(getbufline(a:bufnr, 1, '$'))
    call win_execute(l:sw,
                \ 'call cursor(min([' . a:parent_line . ', ' . l:count . ']), 1)')
    call s:UpdateBlameStatusline()
    call s:UpdateCompactStatusline()
    call s:FinishTrace(a:gen)
    call s:BlameRequest('push', 0)
endfunction

" Backspace：返回较新的层（出栈）
function! s:PopNewer() abort
    call s:InvalidateTrace()
    if len(s:stack) <= 1
        call s:Info('已在工作区层')
        return
    endif
    call s:PopLayer(1)
endfunction

" 出栈一层；show_info 控制是否提示到达工作区层
function! s:PopLayer(show_info) abort
    if len(s:stack) <= 1
        return
    endif
    call remove(s:stack, -1)
    let l:layer = s:stack[-1]
    if !empty(l:layer.commit) && (l:layer.bufnr <= 0
                \ || !bufexists(l:layer.bufnr))
        let s:trace_gen += 1
        let s:trace_busy = 1
        let l:gen = s:trace_gen
        call s:Info('正在重新载入 ' . strpart(l:layer.commit, 0, 10) . ' …')
        call s:GitShowFileAsync(l:layer.commit, l:layer.path,
                    \ {ok, lines -> s:PopLayerReloaded(ok, lines, l:layer,
                    \     a:show_info, l:gen)})
        return
    endif
    call s:FinishPopLayer(l:layer, a:show_info)
endfunction

function! s:PopLayerReloaded(ok, lines, layer, show_info, gen) abort
    if !s:TraceIsCurrent(a:gen, a:layer)
        return
    endif
    if !a:ok
        call s:FinishTrace(a:gen)
        call s:Error('无法重新载入历史版本')
        return
    endif
    let a:layer.bufnr = s:CreateSrcBuffer(a:layer.commit, a:layer.path, a:lines)
    call s:FinishTrace(a:gen)
    call s:FinishPopLayer(a:layer, a:show_info)
endfunction

function! s:FinishPopLayer(layer, show_info) abort
    let l:sw = s:SourceWin()
    if !l:sw
        return
    endif
    call s:ShowLayerInSource(a:layer)
    if !empty(a:layer.commit)
        call s:TouchSrcCache(a:layer.commit . ':' . a:layer.path)
        call s:PruneSrcCache()
    endif
    let l:count = len(getbufline(a:layer.bufnr, 1, '$'))
    call win_execute(l:sw,
                \ 'call cursor(min([' . a:layer.line . ', ' . l:count . ']), 1)')
    call s:UpdateBlameStatusline()
    let l:bw = s:BlameWin()
    if !l:bw
        return
    endif
    if !empty(a:layer.records)
        if a:layer.commit ==# '' && getftime(s:file_path) != a:layer.mtime
            " 工作区文件在追溯期间被改过，重新加载
            call s:BlameRequest('pop', 0)
        else
            call s:ApplyBlameRecords(l:bw, l:sw)
        endif
    else
        call s:BlameRequest('pop', 0)
    endif
    if a:show_info && len(s:stack) == 1
        call s:Info('已回到工作区层')
    endif
endfunction

" 清空历史栈，源窗口切回工作区文件缓冲区（关闭 blame / 退出前调用）
function! s:ClearStack() abort
    call s:InvalidateTrace()
    let l:sw = s:SourceWin()
    let l:line = s:stack[-1].line
    if l:sw && winbufnr(l:sw) != s:file_bufnr
        call win_execute(l:sw, 'noautocmd buffer ' . s:file_bufnr)
        let l:count = line('$', l:sw)
        call win_execute(l:sw,
                    \ 'call cursor(min([' . l:line . ', ' . l:count . ']), 1)')
    endif
    let s:stack = [{'commit': '', 'path': s:rel_path, 'bufnr': s:file_bufnr,
                \ 'records': [], 'line': 1, 'mtime': -1}]
    for l:bufnr in values(s:src_bufs)
        if bufexists(l:bufnr)
            execute 'silent! bwipeout ' . l:bufnr
        endif
    endfor
    let s:src_bufs = {}
    let s:src_cache_order = []
endfunction

function! s:UpdateBlameStatusline() abort
    let l:bw = s:BlameWin()
    if !l:bw
        return
    endif
    let l:depth = 'vimb blame'
    if len(s:stack) > 1
        let l:depth .= '  ' . (len(s:stack) - 1) . ' 层 @'
                    \ . strpart(s:stack[-1].commit, 0, 7)
    endif
    call win_execute(l:bw, 'let &l:statusline = ' . string(' ' . l:depth
                \ . '  |  Enter: commit  Tab: 追溯  BS: 返回  q: close '))
endfunction
