" ---- commit ---------------------------------------------------------------
" 当前查看路径：跟随 blame 历史栈顶层（工作区层为原始路径，历史层为当时的
" 文件路径，rename 追溯时两者不同）
function! s:CurrentPath() abort
    return empty(s:stack) ? s:rel_path : s:stack[-1].path
endfunction

" record 自带的路径属于该 commit 的历史坐标系；rename 之后它可能与当前
" 栈顶路径不同。只有旧格式/合成 record 没有路径时才回退到当前路径。
function! s:RecordPath(record) abort
    let l:path = get(a:record, 'path', '')
    if empty(l:path)
        let l:path = get(a:record, 'filename', '')
    endif
    return empty(l:path) ? s:CurrentPath() : l:path
endfunction

function! s:ShowCommitCmd(hash, file_only, path) abort
    let l:cmd = s:GitBase()
                \ . ' show --no-color --no-ext-diff --no-textconv'
                \ . ' --format=fuller --decorate=no --stat --patch '
                \ . shellescape(a:hash) . ' --'
    if a:file_only
        let l:cmd .= ' ' . shellescape(a:path)
    endif
    return l:cmd . ' 2>&1'
endfunction

function! s:CommitCacheKey(hash, file_only, path) abort
    return a:hash . (a:file_only ? '|file|' . a:path : '|all')
endfunction

function! s:CommitLinesBytes(lines) abort
    let l:bytes = 0
    for l:line in a:lines
        let l:bytes += strlen(l:line) + 1
    endfor
    return l:bytes
endfunction

function! s:TouchCommitCache(key) abort
    let l:index = index(s:commit_cache_order, a:key)
    if l:index >= 0
        call remove(s:commit_cache_order, l:index)
    endif
    call add(s:commit_cache_order, a:key)
endfunction

function! s:CacheCommit(key, lines, file_only) abort
    let l:bytes = s:CommitLinesBytes(a:lines)
    " all-files patch 很容易达到数十 MB；大结果只渲染、不缓存。单文件结果
    " 也不能超过总缓存上限，避免一次提交挤爆 Vim 内存。
    if (!a:file_only && (len(a:lines) > 5000
                \ || l:bytes > s:commit_cache_entry_max_bytes))
                \ || l:bytes > s:commit_cache_max_bytes
        return 0
    endif
    if has_key(s:commit_cache, a:key)
        let s:commit_cache_bytes -= s:commit_cache[a:key].bytes
    endif
    let s:commit_cache[a:key] = {'lines': a:lines, 'bytes': l:bytes}
    let s:commit_cache_bytes += l:bytes
    call s:TouchCommitCache(a:key)
    " 明确的 LRU 顺序 + 总字节上限，条目数上限仅作第二道保护。
    while len(s:commit_cache_order) > 10
                \ || s:commit_cache_bytes > s:commit_cache_max_bytes
        let l:oldest = remove(s:commit_cache_order, 0)
        let s:commit_cache_bytes -= s:commit_cache[l:oldest].bytes
        call remove(s:commit_cache, l:oldest)
    endwhile
    return 1
endfunction

function! s:LoadCommitLines(hash, file_only, path, on_done) abort
    let l:key = s:CommitCacheKey(a:hash, a:file_only, a:path)
    if has_key(s:commit_cache, l:key)
        call s:TouchCommitCache(l:key)
        return call(a:on_done, [1, s:commit_cache[l:key].lines])
    endif
    return s:GitLines(s:ShowCommitCmd(a:hash, a:file_only, a:path),
                \ {ok, lines -> ok
                \     ? s:CacheCommitThenCall(l:key, lines, a:file_only,
                \         a:on_done)
                \     : call(a:on_done, [ok, lines])}, 'commit')
endfunction

function! s:CacheCommitThenCall(key, lines, file_only, on_done) abort
    call s:CacheCommit(a:key, a:lines, a:file_only)
    return call(a:on_done, [1, a:lines])
endfunction

function! s:ClipAndPad(text, width) abort
    let l:text = substitute(a:text, '\s\+', ' ', 'g')
    if strdisplaywidth(l:text) <= a:width
        return l:text . repeat(' ', a:width - strdisplaywidth(l:text))
    endif
    let l:result = ''
    for l:char in split(l:text, '\zs')
        if strdisplaywidth(l:result . l:char . '…') > a:width
            break
        endif
        let l:result .= l:char
    endfor
    let l:result .= '…'
    return l:result . repeat(' ', max([0, a:width - strdisplaywidth(l:result)]))
endfunction

function! s:BlameDisplayLines(records) abort
    if empty(a:records)
        return ['(空文件：没有可显示的 blame 信息)']
    endif
    let l:number_width = max([4, strlen(string(len(a:records)))])
    let l:lines = []
    let l:last_hash = ''
    for l:record in a:records
        " 连续相同 commit 的行只保留行号，块信息在块首行显示一次，
        " 便于扫读；b:vimb_records 仍逐行完整保留
        let l:compact = l:record.hash ==# l:last_hash
        let l:hash = l:compact ? '' :
                    \ (l:record.hash =~# '^0\+$'
                    \     ? 'WORKTREE'
                    \     : strpart(l:record.hash, 0, 10))
        let l:date = l:compact ? '' :
                    \ (get(l:record, 'author_time', 0) > 0
                    \     ? strftime('%Y-%m-%d', l:record.author_time)
                    \     : '----------')
        let l:author = l:compact ? '' : get(l:record, 'author', '?')
        " 作者列必须按显示宽度填充：printf %-12s 按字节填充，中文等
        " 宽字符作者的日期/行号列会整体左移错位；hash/日期恒为 ASCII
        let l:prefix = printf('%-10s ', l:hash)
                    \ . s:ClipAndPad(l:author, 12) . ' '
                    \ . printf('%-10s ', l:date)
        call add(l:lines, l:prefix . printf('%*d', l:number_width,
                    \ get(l:record, 'final_line', len(l:lines) + 1)))
        let l:last_hash = l:record.hash
    endfor
    return l:lines
endfunction

function! s:ReplaceCurrentBuffer(lines) abort
    setlocal modifiable
    silent %delete _
    call setline(1, empty(a:lines) ? [''] : a:lines)
    setlocal nomodifiable
    setlocal nomodified
endfunction

function! s:PopulateBlame(records) abort
    let b:vimb_records = deepcopy(a:records)
    " hash → [行号...] 索引：光标移动时高亮从 O(n) 扫描降为 O(1) 查找
    let b:vimb_hash_lines = {}
    let l:index = 0
    for l:record in a:records
        if !has_key(b:vimb_hash_lines, l:record.hash)
            let b:vimb_hash_lines[l:record.hash] = []
        endif
        call add(b:vimb_hash_lines[l:record.hash], l:index + 1)
        let l:index += 1
    endfor
    call s:ReplaceCurrentBuffer(s:BlameDisplayLines(a:records))
    call s:DefineBlameSyntax(a:records)
endfunction
