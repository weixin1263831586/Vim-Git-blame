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
                \ 'File     ' . s:RecordPath(l:record),
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
    let l:backend = s:CopyText(l:hash)
    call s:Info('已复制 ' . strpart(l:hash, 0, 12)
                \ . s:ClipboardStatus(l:backend))
endfunction

" 无 job 支持时的同步回退。
function! s:RunClipboardCommand(command, text) abort
    try
        call system(a:command, a:text)
        return v:shell_error == 0
    catch
        return 0
    endtry
endfunction

function! s:ClipboardJobDone(token, status) abort
    if !has_key(s:clipboard_jobs, a:token)
        return
    endif
    let l:state = remove(s:clipboard_jobs, a:token)
    " DISPLAY 存在不等于 X11 连接可用。后台命令失败时，
    " clipboard 主任务再回退 OSC 52；primary 只是尽力而为。
    if a:status != 0 && get(l:state, 'fallback', 0)
        call s:SendOSC52(l:state.text)
    endif
endfunction

" X11 转发下 xclip 取得 selection ownership 常需 1–2 秒。
" clipboard 和 primary 串行 system() 会冻结 Vim 约 4 秒，使选区看起来
" 没有生效。用 job 同时启动两个 owner，立即把界面控制权还给用户。
function! s:StartClipboardJob(command, text, fallback) abort
    if !has('job') || !exists('*ch_sendraw') || !exists('*ch_close_in')
        return 0
    endif
    let s:clipboard_job_seq += 1
    let l:token = s:clipboard_job_seq
    let s:clipboard_jobs[l:token] = {'job': 0, 'text': a:text,
                \ 'fallback': a:fallback}
    let l:job = job_start(['/bin/sh', '-c', a:command], {
                \ 'in_io': 'pipe',
                \ 'out_io': 'null',
                \ 'err_io': 'null',
                \ 'exit_cb': {job, status -> s:ClipboardJobDone(
                \     l:token, status)},
                \ })
    if type(l:job) == v:t_number && l:job == 0
        call remove(s:clipboard_jobs, l:token)
        return 0
    endif
    let s:clipboard_jobs[l:token].job = l:job
    try
        let l:channel = job_getchannel(l:job)
        call ch_sendraw(l:channel, a:text)
        call ch_close_in(l:channel)
    catch
        call remove(s:clipboard_jobs, l:token)
        try
            call job_stop(l:job)
        catch
        endtry
        return 0
    endtry
    return 1
endfunction

function! s:CopyWithClipboardJob(command, text, fallback) abort
    return s:StartClipboardJob(a:command, a:text, a:fallback)
                \ || s:RunClipboardCommand(a:command, a:text)
endfunction

function! s:CopyWithNativeClipboard(text) abort
    if executable('wl-copy') && $WAYLAND_DISPLAY !=# ''
        return s:CopyWithClipboardJob('wl-copy', a:text, 1)
                    \ ? 'wl-copy' : ''
    elseif executable('xclip') && $DISPLAY !=# ''
        if !s:CopyWithClipboardJob(
                    \ 'xclip -selection clipboard -in', a:text, 1)
            return ''
        endif
        " X11 主选择区（鼠标中键粘贴）与 Vim autoselect 的原生行为对齐；
        " primary 尽力而为，失败不影响 clipboard 结果。
        call s:CopyWithClipboardJob(
                    \ 'xclip -selection primary -in', a:text, 0)
        return 'xclip'
    elseif executable('xsel') && $DISPLAY !=# ''
        if !s:CopyWithClipboardJob(
                    \ 'xsel --clipboard --input', a:text, 1)
            return ''
        endif
        call s:CopyWithClipboardJob('xsel --primary --input', a:text, 0)
        return 'xsel'
    elseif executable('pbcopy')
        return s:CopyWithClipboardJob('pbcopy', a:text, 1) ? 'pbcopy' : ''
    elseif executable('termux-clipboard-set')
        return s:CopyWithClipboardJob('termux-clipboard-set', a:text, 1)
                    \ ? 'termux' : ''
    elseif executable('clip.exe')
        return s:CopyWithClipboardJob('clip.exe', a:text, 1) ? 'clip.exe' : ''
    endif
    return ''
endfunction

function! s:SendOSC52(text) abort
    if has('gui_running') || !executable('base64') || strlen(a:text) > 100000
        return 0
    endif
    try
        " system() 保留 base64 的末尾换行；writefile() 会把字符串内
        " 的换行编码成 NUL，导致 OSC 52 序列被终端拒绝。systemlist()
        " 先按行拆分，再拼接成纯 base64 payload。
        let l:encoded = join(systemlist('base64', a:text), '')
        if empty(l:encoded)
            return 0
        endif
        call writefile(["\x1b]52;c;" . l:encoded . "\x07"], '/dev/tty', 'b')
        return 1
    catch
        return 0
    endtry
endfunction

function! s:ClipboardStatus(backend) abort
    if a:backend ==# 'register'
        return '（系统剪贴板）'
    elseif a:backend ==# 'osc52'
        return '（已发送 OSC 52 请求）'
    elseif a:backend !=# 'vim'
        return '（系统剪贴板：' . a:backend . '）'
    endif
    return '（仅 Vim 寄存器）'
endfunction

" 始终写 Vim unnamed register。+/* 寄存器只有在 Vim 编译了真实 clipboard
" 支持时才代表系统剪贴板；没有该特性时寄存器只是 Vim 内部存储，回读校验
" 不可信，必须继续尝试可验证的本地剪贴板命令，最后才回退到无法从应用侧
" 确认是否被终端接受的 OSC 52。
function! s:CopyText(text) abort
    let @" = a:text
    if has('clipboard')
        for l:reg in ['+', '*']
            try
                call setreg(l:reg, a:text)
            catch
            endtry
        endfor
        if getreg('+') ==# a:text
            return 'register'
        endif
    endif
    let l:native = s:CopyWithNativeClipboard(a:text)
    if !empty(l:native)
        return l:native
    endif
    return s:SendOSC52(a:text) ? 'osc52' : 'vim'
endfunction

" 释放左键时的统一复制入口。Visual 模式下按键映射里的 Ex 命令执行前，
" Vim 会先把选区转成 '< '> 标记并退出 Visual——所以这里不检查 mode()，
" 直接用 gvy 取回完整选区（双击选词 / 三击选行 / 拖拽选区都覆盖），
" 复制完成后再 gv 恢复选区高亮，与原生 Vim 的双击体验一致。
function! s:CopyMouseSelection() abort
    call s:CancelMouseClick()
    if line("'<") <= 0 || line("'>") <= 0
        return
    endif
    silent normal! gvy
    let l:text = @"
    if empty(l:text)
        return
    endif
    " 先恢复并绘制选区，再等待 xclip/wl-copy 等系统剪贴板命令。
    " SSH/X11 下 xclip 可能需要一两秒；若先复制后 gv，期间屏幕没有任何
    " 选中反馈，会被误认为没有响应。
    silent normal! gv
    redraw
    let l:backend = s:CopyText(l:text)
    call s:Info('已复制 ' . s:ClipDisplayText(
                \ substitute(l:text, '\n', ' ', 'g'), 40)
                \ . s:ClipboardStatus(l:backend))
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
