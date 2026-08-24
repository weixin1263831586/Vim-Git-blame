" ---- blame 历史栈 ----------------------------------------------------------
" P0 正确性：original_line 是子 commit 中的行号，不等于父 commit 中对应
" 旧行的行号（父版本前后可能有插入/删除）。这里通过
"   git diff --unified=0 <prev>:<prev_path> <cur>:<cur_path>
" 的 hunk 头建立 child→parent 行映射；落在新增区（old_count == 0）的行
" 是本 commit 首次引入，返回 -1（Tab 应提示而不是误追）。
function! s:MapChildLineToParent(diff_lines, child_line) abort
    let l:hunks = []
    for l:raw in a:diff_lines
        let l:m = matchlist(l:raw,
                    \ '^@@ -\(\d\+\)\%(,\(\d\+\)\)\? +\(\d\+\)\%(,\(\d\+\)\)\? @@')
        if !empty(l:m)
            call add(l:hunks, {
                        \ 'old_start': str2nr(l:m[1]),
                        \ 'old_count': l:m[2] ==# '' ? 1 : str2nr(l:m[2]),
                        \ 'new_start': str2nr(l:m[3]),
                        \ 'new_count': l:m[4] ==# '' ? 1 : str2nr(l:m[4])})
        endif
    endfor
    if empty(l:hunks)
        return a:child_line
    endif
    " new_start 已经是 child revision 的绝对行号；delta 只用于 hunk 之间
    " 的未改动区，绝不能再次加到 new_start/new_end 上。
    let l:delta = 0
    for l:h in l:hunks
        let l:child_end = l:h.new_start + l:h.new_count - 1
        if a:child_line < l:h.new_start
            return a:child_line - l:delta
        endif
        if l:h.new_count > 0 && a:child_line <= l:child_end
            if l:h.old_count == 0
                return -1   " 新增行：本 commit 首次引入
            endif
            let l:child_index = a:child_line - l:h.new_start
            if l:child_index < min([l:h.old_count, l:h.new_count])
                return l:h.old_start + l:child_index
            endif
            " replacement 中超出旧范围的 child 行也是本 commit 新增。
            return -1
        endif
        let l:delta += l:h.new_count - l:h.old_count
    endfor
    return a:child_line - l:delta
endfunction

" 取子/父两个版本间的 diff hunk（异步）；回调 on_done(ok, parent_line, lines)
" parent_line == -1 表示该行为本 commit 新增
function! s:ChildToParentLineAsync(child_commit, child_path, record, on_done) abort
    let l:prev = a:record.previous
    let l:prev_path = get(a:record, 'previous_path', '')
    if l:prev_path ==# ''
        let l:prev_path = a:child_path
    endif
    let l:cmd = s:GitBase() . ' diff --unified=0 '
                \ . shellescape(l:prev . ':' . l:prev_path) . ' '
                \ . shellescape(a:child_commit . ':' . a:child_path) . ' 2>&1'
    call s:GitLines(l:cmd, {ok, lines ->
                \ call(a:on_done, [ok, s:MapChildLineToParent(lines,
                \     get(a:record, 'original_line', 1)), lines])})
endfunction

" git show <commit>:<path> 异步读取文件内容；回调 on_done(ok, lines)
function! s:GitShowFileAsync(commit, path, on_done) abort
    let l:cmd = s:GitBase()
                \ . ' show ' . shellescape(a:commit . ':' . a:path) . ' 2>&1'
    call s:GitLines(l:cmd, a:on_done)
endfunction

" 取历史版本缓冲区（懒创建并缓存）。同步读取已移除：内容由调用方经
" GitShowFileAsync 取得后经 CreateSrcBuffer 落地。
function! s:CreateSrcBuffer(commit, path, lines) abort
    let l:key = a:commit . ':' . a:path
    if has_key(s:src_bufs, l:key) && bufexists(s:src_bufs[l:key])
        return s:src_bufs[l:key]
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
    if has_key(s:src_bufs, l:key) && bufexists(s:src_bufs[l:key])
        call s:FinishPush(l:prev, l:prev_path, s:src_bufs[l:key],
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
    let l:sw = s:SourceWin()
    if !l:sw
        return
    endif
    call s:ShowLayerInSource(l:layer)
    let l:count = len(getbufline(l:layer.bufnr, 1, '$'))
    call win_execute(l:sw,
                \ 'call cursor(min([' . l:layer.line . ', ' . l:count . ']), 1)')
    call s:UpdateBlameStatusline()
    let l:bw = s:BlameWin()
    if !l:bw
        return
    endif
    if !empty(l:layer.records)
        if l:layer.commit ==# '' && getftime(s:file_path) != l:layer.mtime
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

