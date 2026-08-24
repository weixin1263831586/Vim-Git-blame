" ---- 快捷操作: i / y / o ---------------------------------------------------
" 当前上下文的 record 与 hash（blame 窗口 / 源窗口 / commit 面板各取各的）
function! s:FocusRecord() abort
    if win_getid() == s:BlameWin()
        return s:CurrentRecord()
    elseif win_getid() == s:SourceWin()
        return s:CurrentLayerRecord()
    elseif s:WindowMatches(s:history_winid, s:history_bufnr)
                \ && win_getid() == s:history_winid
        return s:CurrentHistoryRecord()
    endif
    return {}
endfunction

function! s:FocusHash() abort
    if win_getid() == s:CommitWin() && exists('b:vimb_hash')
        return b:vimb_hash
    endif
    let l:record = s:FocusRecord()
    return empty(l:record) ? '' : l:record.hash
endfunction

" i：轻量 commit 信息（纯内存，零 Git 调用）
function! s:CommitInfo() abort
    let l:record = s:FocusRecord()
    if empty(l:record)
        call s:Error('当前行没有 blame 信息')
        return
    endif
    if l:record.hash =~# '^0\+$'
        call s:Info('该行是未提交的工作区内容')
        return
    endif
    let l:mail = substitute(get(l:record, 'author_mail', ''), '^<\|>$', '', 'g')
    let l:date = get(l:record, 'author_time', 0) > 0
                \ ? strftime('%Y-%m-%d %H:%M', l:record.author_time) : ''
    let l:lines = [
                \ 'Commit   ' . strpart(l:record.hash, 0, 12),
                \ 'Author   ' . get(l:record, 'author', '?')
                \ . (empty(l:mail) ? '' : '  <' . l:mail . '>'),
                \ 'Date     ' . l:date,
                \ 'File     ' . (empty(s:stack) ? s:rel_path : s:stack[-1].path),
                \ ]
    if get(l:record, 'previous', '') !=# ''
        call add(l:lines, 'Prev     ' . strpart(l:record.previous, 0, 12)
                    \ . '  (' . get(l:record, 'previous_path', '') . ')')
    endif
    call add(l:lines, '')
    call add(l:lines, get(l:record, 'summary', ''))
    if exists('*popup_atcursor')
        call popup_atcursor(l:lines, {'moved': 'any', 'padding': [0, 1, 0, 1],
                    \ 'border': [], 'borderchars': [' '], 'wrap': 0})
    else
        echo join(l:lines, "\n")
    endif
endfunction

" y：复制当前 commit 完整 SHA
function! s:YankHash() abort
    let l:hash = s:FocusHash()
    if empty(l:hash)
        call s:Error('当前位置没有可复制的 commit')
        return
    endif
    if l:hash =~# '^0\+$'
        call s:Info('该行是未提交的工作区内容，没有 commit 可复制')
        return
    endif
    let @" = l:hash
    for l:reg in ['+', '*']
        try
            call setreg(l:reg, l:hash)
        catch
        endtry
    endfor
    call s:Info('已复制 ' . strpart(l:hash, 0, 12)
                \ . (empty(@+) ? '' : '（含系统剪贴板）'))
endfunction

" o：在浏览器打开 commit
" Web 基址覆盖优先级：VIMB_WEB_BASE_URL 环境变量 > git config vimb.webBaseUrl
" （Gerrit 的 SSH 端口 29418 无法直接推出 Web 端口，自建实例建议配置其一）
let s:remote_url = ''
function! s:WebBaseOverride() abort
    if $VIMB_WEB_BASE_URL !=# ''
        return $VIMB_WEB_BASE_URL
    endif
    let l:cfg = systemlist('git --no-pager -C ' . shellescape(s:git_root)
                \ . ' config --get vimb.webBaseUrl 2>/dev/null')
    if !v:shell_error && !empty(l:cfg) && l:cfg[0] !=# ''
        return substitute(l:cfg[0], '/$', '', '')
    endif
    return ''
endfunction

function! s:CommitWebURL(hash) abort
    if a:hash =~# '^0\+$'
        return ''
    endif
    let l:base = s:WebBaseOverride()
    if s:remote_url ==# ''
        let l:out = systemlist('git --no-pager -C ' . shellescape(s:git_root)
                    \ . ' remote get-url origin 2>/dev/null')
        if v:shell_error || empty(l:out)
            throw '无法获取 origin 远端 URL（git remote get-url origin 失败）'
        endif
        let s:remote_url = l:out[0]
    endif
    let l:url = s:remote_url
    " ssh://user@host:port/path(.git)（Gerrit 常见 user 非 git、端口 29418）
    let l:m = matchlist(l:url, '^ssh://[^@/]\+@\([^:/]\+\)\%(:\d\+\)\?/\(.\+\)$')
    if empty(l:m)
        " user@host:path(.git)（scp 风格）
        let l:m = matchlist(l:url, '^\%(ssh://\)\?[^@/]\+@\([^:/]\+\)[/:]\(.\+\)$')
    endif
    if empty(l:m)
        let l:m = matchlist(l:url, '^https\?://\([^/]\+\)/\(.\+\)$')
    endif
    if empty(l:m)
        throw '无法解析远端 URL: ' . l:url
    endif
    let l:host = l:m[1]
    let l:path = substitute(l:m[2], '\.git$', '', '')
    " Gerrit：优先用显式 Web 基址（SSH host 可能与 Web host 不同）
    if l:host =~# '^gerrit\.\|[-.]gerrit\.' || l:base !=# ''
        let l:root = (l:base !=# '' ? l:base : 'https://' . l:host)
        return l:root . '/c/' . l:path . '/+/' . a:hash
    endif
    if l:host =~# '\<github\.com$'
        return 'https://' . l:host . '/' . l:path . '/commit/' . a:hash
    elseif l:host =~# '\<gitlab\.[^./]*\|\<gitlab\>'
        return 'https://' . l:host . '/' . l:path . '/-/commit/' . a:hash
    elseif l:host =~# '\<gitee\.com$'
        return 'https://' . l:host . '/' . l:path . '/commit/' . a:hash
    elseif l:host =~# '\<bitbucket\.org$'
        return 'https://' . l:host . '/' . l:path . '/commits/' . a:hash
    elseif l:host =~# '\<sr\.ht$'
        return 'https://' . l:host . '/' . l:path . '/commit/' . a:hash
    endif
    throw '未识别的远端类型: ' . l:url
endfunction

function! s:OpenInBrowser() abort
    let l:hash = s:FocusHash()
    if empty(l:hash)
        call s:Error('当前位置没有可打开的 commit')
        return
    endif
    try
        let l:url = s:CommitWebURL(l:hash)
    catch
        call s:Error(substitute(v:exception, '^Vim\%((\w*)\)\=:', '', '')
                    \ . '；可手动用 o 前先确认远端配置')
        return
    endtry
    let l:runner = executable('xdg-open') ? 'xdg-open'
                \ : executable('open') ? 'open' : ''
    if empty(l:runner)
        call s:Info('未找到 xdg-open/open，URL: ' . l:url)
        return
    endif
    call system(l:runner . ' ' . shellescape(l:url) . ' &')
    call s:Info('已打开 ' . l:url)
endfunction
command! -nargs=1 VimbCommitURL echo <SID>CommitWebURL(<f-args>)
