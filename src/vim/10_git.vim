" ---- Git 执行层 -----------------------------------------------------------
" on_done(ok, lines)：所有调用方统一通过回调拿结果，同步/异步无差别。
function! s:GitLinesSync(cmd, on_done) abort
    let l:lines = systemlist(a:cmd)
    return call(a:on_done, [v:shell_error == 0, l:lines])
endfunction

function! s:JobDone(token) abort
    if !has_key(s:jobs, a:token)
        return
    endif
    let l:state = remove(s:jobs, a:token)
    " out_cb 每次回调恰为一行（不含换行符），无需再切分
    let l:exitval = l:state.exitval
    if l:exitval == -1 && job_info(l:state.job).status ==# 'dead'
        let l:exitval = job_info(l:state.job).exitval
    endif
    call call(l:state.on_done, [l:exitval == 0, l:state.chunks])
endfunction

function! s:GitLinesAsync(cmd, on_done) abort
    let s:job_seq += 1
    let l:token = s:job_seq
    let s:jobs[l:token] = {'chunks': [], 'on_done': a:on_done, 'exitval': -1,
                \ 'job': 0}
    " 注意 1：job_start() 对字符串命令不经 shell 执行，2>&1 等重定向会变成
    " 字面参数，必须显式走 sh -c。
    " 注意 2：exit_cb 触发时 out_cb 可能尚未派发完（大数据量竞态），
    " 结果统一在 close_cb（通道关闭、输出消费完毕）时派发。
    let l:job = job_start(['/bin/sh', '-c', a:cmd], {
        \ 'out_cb': {j, d -> has_key(s:jobs, l:token)
        \     ? add(s:jobs[l:token].chunks, d) : 0},
        \ 'exit_cb': {j, st -> has_key(s:jobs, l:token)
        \     ? extend(s:jobs[l:token], {'exitval': job_info(j).exitval}) : 0},
        \ 'close_cb': {ch -> s:JobDone(l:token)},
        \ })
    if type(l:job) != v:t_number
        let s:jobs[l:token].job = l:job
    endif
    if type(l:job) == v:t_number && l:job == 0
        call remove(s:jobs, l:token)
        call s:Error('无法启动后台 Git 任务，回退同步执行')
        return s:GitLinesSync(a:cmd, a:on_done)
    endif
    return 1
endfunction

function! s:GitLines(cmd, on_done) abort
    return s:async ? s:GitLinesAsync(a:cmd, a:on_done)
                \ : s:GitLinesSync(a:cmd, a:on_done)
endfunction

let s:blame_args = $VIMB_BLAME_ARGS

" ---- blame ----------------------------------------------------------------
function! s:BlameCmd(commit, path) abort
    let l:cmd = s:GitBase()
                \ . ' blame --no-ext-diff --no-textconv --line-porcelain'
    if s:blame_args !=# ''
        let l:cmd .= ' ' . join(map(split(s:blame_args),
                    \ 'shellescape(v:val)'), ' ')
    endif
    if a:commit !=# ''
        let l:cmd .= ' ' . shellescape(a:commit)
    endif
    return l:cmd . ' -- ' . shellescape(a:path) . ' 2>&1'
endfunction

function! s:ParseBlameLines(lines) abort
    let l:records = []
    let l:record = {}
    for l:raw in a:lines
        let l:header = matchlist(l:raw,
                    \ '^\([0-9a-f]\{40,64}\) \(\d\+\) \(\d\+\)\%(\s\+\d\+\)\?$')
        if !empty(l:header)
            let l:record = {
                        \ 'hash': l:header[1],
                        \ 'original_line': str2nr(l:header[2]),
                        \ 'final_line': str2nr(l:header[3]),
                        \ 'author': '',
                        \ 'author_time': 0,
                        \ 'author_mail': '',
                        \ 'previous': '',
                        \ 'previous_path': '',
                        \ 'filename': '',
                        \ 'summary': ''}
        elseif empty(l:record)
            continue
        elseif stridx(l:raw, 'author ') == 0
            let l:record.author = strpart(l:raw, 7)
        elseif stridx(l:raw, 'author-mail ') == 0
            let l:record.author_mail = strpart(l:raw, 12)
        elseif stridx(l:raw, 'author-time ') == 0
            let l:record.author_time = str2nr(strpart(l:raw, 12))
        elseif stridx(l:raw, 'summary ') == 0
            let l:record.summary = strpart(l:raw, 8)
        elseif stridx(l:raw, 'previous ') == 0
            let l:prev = matchlist(strpart(l:raw, 9), '^\(\x\{40,64}\) \(.*\)$')
            if !empty(l:prev)
                let l:record.previous = l:prev[1]
                let l:record.previous_path = s:DecodeGitQuotedPath(l:prev[2])
            endif
        elseif stridx(l:raw, 'filename ') == 0
            let l:record.filename = s:DecodeGitQuotedPath(strpart(l:raw, 9))
        elseif stridx(l:raw, "\t") == 0
            let l:record.text = strpart(l:raw, 1)
            call add(l:records, l:record)
            let l:record = {}
        endif
    endfor
    return l:records
endfunction

