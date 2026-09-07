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
    if has_key(l:state, 'next')
        " 同一剪贴板串行写入，只保留最新待写文本，防止慢的旧任务覆盖新选区。
        call s:CopyWithClipboardJob(l:state.command,
                    \ l:state.next.text, l:state.next.fallback)
        return
    endif
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
    for l:state in values(s:clipboard_jobs)
        if l:state.command ==# a:command
            let l:state.next = {'text': a:text, 'fallback': a:fallback}
            return 1
        endif
    endfor
    let s:clipboard_job_seq += 1
    let l:token = s:clipboard_job_seq
    let s:clipboard_jobs[l:token] = {'job': 0, 'text': a:text,
                \ 'fallback': a:fallback, 'command': a:command}
    let l:job = job_start(['/bin/sh', '-c', a:command], {
                \ 'in_io': 'pipe',
                \ 'out_io': 'null',
                \ 'err_io': 'null',
                \ 'exit_cb': {job, status -> s:ClipboardJobDone(
                \     l:token, status)},
                \ })
    if (type(l:job) == v:t_number && l:job == 0) || job_status(l:job) ==# 'fail'
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
        if !s:CopyWithClipboardJob('wl-copy', a:text, 1)
            return ''
        endif
        call s:CopyWithClipboardJob('wl-copy --primary', a:text, 0)
        return 'wl-copy'
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
function! s:CopyText(text, ...) abort
    let l:type = a:0 ? a:1 : 'v'
    call setreg('"', a:text, l:type)
    if has('clipboard')
        for l:reg in ['+', '*']
            try
                call setreg(l:reg, a:text, l:type)
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

" ---- 观察式选区复制 --------------------------------------------------------
" <LeftMouse>/<LeftDrag>/<LeftRelease> 及双击/三击/四击全部保持 Vim 原生
" 行为，不做任何映射。全局 CursorMoved/ModeChanged 只是旁路观察：选区
" 一变化就重启 120ms 防抖定时器，光标静止（选区稳定）后才复制。读取选区
" 用 getpos('.')/getpos('v') 纯函数计算，不执行 normal!，不写 '< '> 标记，
" 不打断进行中的选区（双击释放后高亮原样保留）。

function! s:InstallVisualObserver() abort
    call s:RemoveVisualObserver()
    augroup VimbObserver
        autocmd!
        autocmd CursorMoved * call <SID>OnSelectionMotion()
        if exists('##ModeChanged')
            autocmd ModeChanged * call <SID>OnSelectionMotion()
        endif
        autocmd WinLeave,BufLeave * call <SID>ResetVisualCopy()
    augroup END
    " 只动锚点（如右键扩展）或旧版 Vim 缺少 ModeChanged 时，CursorMoved
    " 不一定触发。轻量轮询比较坐标，文本仅在选区稳定时读取一次。
    if exists('*timer_start')
        let s:visual_observer_timer = timer_start(60,
                    \ {timer -> s:OnSelectionMotion()}, {'repeat': -1})
    endif
endfunction

function! s:RemoveVisualObserver() abort
    augroup VimbObserver
        autocmd!
    augroup END
    if s:visual_observer_timer != -1 && exists('*timer_stop')
        call timer_stop(s:visual_observer_timer)
    endif
    let s:visual_observer_timer = -1
    call s:ResetVisualCopy()
endfunction

function! s:ResetVisualCopy() abort
    call s:CancelVisualCopyTimer()
    let s:visual_signature = []
    let s:last_visual_copy = ''
endfunction

function! s:CancelVisualCopyTimer() abort
    if s:visual_copy_timer != -1 && exists('*timer_stop')
        call timer_stop(s:visual_copy_timer)
    endif
    let s:visual_copy_timer = -1
endfunction

function! s:OnSelectionMotion() abort
    if !s:SelectionActive() || !s:VisualGateBuffer()
        " 已离开选区：停表，并允许下一次选区重新复制相同文本
        call s:ResetVisualCopy()
        return
    endif
    let l:signature = [win_getid(), bufnr('%'), b:changedtick, mode(1),
                \ getpos('v'), getpos('.'), &selection, &virtualedit,
                \ &tabstop, &vartabstop, winsaveview().curswant]
    if l:signature ==# s:visual_signature
        return
    endif
    let s:visual_signature = l:signature
    " 双击/拖拽先进入 Visual：单击打开 commit 面板的待判定定时器让位
    call s:CancelMouseClick()
    call s:CancelVisualCopyTimer()
    if exists('*timer_start')
        let s:visual_copy_timer = timer_start(120,
                    \ {timer -> s:VisualCopyTick(timer)})
    endif
endfunction

function! s:VisualCopyTick(timer) abort
    let s:visual_copy_timer = -1
    if s:SelectionActive()
        call s:CopyStableSelection()
    endif
endfunction

" 测试钩子：立即执行一次“选区已稳定”复制（等同防抖定时器到期）
function! s:VisualCopyNow() abort
    call s:CopyStableSelection()
endfunction

function! s:CopyStableSelection() abort
    if !s:VisualGateBuffer()
        return
    endif
    " 选区进行中读实时选区；刚结束（防抖 tick 落在退出之后）读 '< '>
    if !s:SelectionActive() && line("'<") <= 0
        return
    endif
    let l:text = s:VisualSelectionText()
    let l:type = s:VisualSelectionType()
    if l:type ==# nr2char(22)
        let l:bounds = s:VisualBlockBounds(
                    \ s:SelectionActive() ? getpos('v') : getpos("'<"),
                    \ s:SelectionActive() ? getpos('.') : getpos("'>"))
        let l:type .= max([1, l:bounds[1] - l:bounds[0] + 1])
    endif
    let l:copy = string([l:type, l:text])
    if empty(l:text) || l:copy ==# s:last_visual_copy
        return
    endif
    let s:last_visual_copy = l:copy
    " 自动复制不 echo，保留 Vim 原生的 Visual/Select 模式提示。
    call s:CopyText(l:text, l:type)
endfunction

function! s:VisualSelectionType() abort
    let l:kind = s:SelectionActive() ? mode(1) : visualmode()
    return get({'s': 'v', 'S': 'V', nr2char(19): nr2char(22)}, l:kind, l:kind)
endfunction

" 纯函数读取当前 Visual/Select 选区文本（结果等价于对应模式的 yank）。
" 选区进行中用 'v' 标记与光标；刚离开选区（Ex 命令会把 Visual 转成
" '< '> 标记并退出，脚本/定时器上下文无法避免）则回退读 '< '> 与
" visualmode()，两者描述的是同一个选区。
function! s:VisualSelectionText() abort
    let l:kind = s:VisualSelectionType()
    if s:SelectionActive()
        let l:anchor = getpos('v')
        let l:cursor = getpos('.')
    else
        let l:anchor = getpos("'<")
        let l:cursor = getpos("'>")
    endif
    if l:anchor[1] <= 0 || l:cursor[1] <= 0
        return ''
    endif
    let l:sl = min([l:anchor[1], l:cursor[1]])
    let l:el = max([l:anchor[1], l:cursor[1]])
    if l:kind ==# 'V'
        return join(getline(l:sl, l:el), "\n") . "\n"
    endif
    if l:kind ==# nr2char(22)
        let l:virtual = &virtualedit =~# '\<\(all\|block\)\>'
        let [l:left, l:right] = s:VisualBlockBounds(l:anchor, l:cursor)
        let l:parts = []
        for l:n in range(l:sl, l:el)
            call add(l:parts, s:SliceScreenCols(getline(l:n), l:left, l:right,
                        \ l:virtual))
        endfor
        return join(l:parts, "\n")
    endif
    if exists('*getregion')
        " getregion 会省略 exclusive 选区在下一行第 1 列的空尾段；
        " yank 的字符寄存器仍保留前一行换行。
        let l:end = l:anchor[1] > l:cursor[1] ? l:anchor : l:cursor
        let l:linebreak = &selection ==# 'exclusive' && l:sl < l:el
                    \ && l:end[2] == 1 ? "\n" : ''
        return join(getregion(l:anchor, l:cursor,
                    \ {'type': l:kind, 'exclusive': &selection ==# 'exclusive'}), "\n")
                    \ . l:linebreak . s:VisualTrailingNewline(l:anchor, l:cursor)
    endif
    " 起止列：跨行时各自取所在行的端点，同行时按列序（可反向选择）
    if l:anchor[1] < l:cursor[1]
        let l:sc = l:anchor[2]
        let l:ec = l:cursor[2]
    elseif l:cursor[1] < l:anchor[1]
        let l:sc = l:cursor[2]
        let l:ec = l:anchor[2]
    else
        let l:sc = min([l:anchor[2], l:cursor[2]])
        let l:ec = max([l:anchor[2], l:cursor[2]])
    endif
    let l:exclusive = &selection ==# 'exclusive'
                \ && (l:sl != l:el || l:sc != l:ec)
    " 字符-wise：锚点行从锚点列起，止于光标字符（含）
    let l:parts = []
    for l:n in range(l:sl, l:el)
        let l:c1 = l:n == l:sl ? l:sc : 1
        let l:c2 = l:n == l:el ? l:ec : strlen(getline(l:n)) + 1
        if l:n == l:el && l:exclusive
            call add(l:parts, strpart(getline(l:n), l:c1 - 1, l:c2 - l:c1))
        else
            call add(l:parts, s:SliceVisualCols(getline(l:n), l:c1, l:c2))
        endif
    endfor
    return join(l:parts, "\n") . s:VisualTrailingNewline(l:anchor, l:cursor)
endfunction

function! s:VisualBlockBounds(anchor, cursor) abort
    let l:virtual = &virtualedit =~# '\<\(all\|block\)\>'
    let l:reverse = a:anchor[1] > a:cursor[1]
                \ || (a:anchor[1] == a:cursor[1] && a:anchor[2] > a:cursor[2])
    let l:a = s:VisualScreenSpan(l:reverse ? a:cursor : a:anchor, l:virtual)
    let l:c = s:VisualScreenSpan(l:reverse ? a:anchor : a:cursor, l:virtual)
    let l:left = min([l:a[0], l:c[0]])
    let l:right = max([l:a[1], l:c[1]])
    " 与 Vim block operator 一致：按缓冲区位置排序后，仅缩短右伸的终点。
    if &selection ==# 'exclusive' && l:c[0] > l:a[1]
        let l:right = l:c[0] - 1
    endif
    if winsaveview().curswant == 2147483647
        let l:lines = getline(min([a:anchor[1], a:cursor[1]]),
                    \ max([a:anchor[1], a:cursor[1]]))
        let l:right = max(map(l:lines, 'strdisplaywidth(v:val)')) + 1
    endif
    return [l:left, l:right]
endfunction

function! s:VisualTrailingNewline(anchor, cursor) abort
    let l:end = a:anchor[1] > a:cursor[1]
                \ || (a:anchor[1] == a:cursor[1] && a:anchor[2] > a:cursor[2])
                \ ? a:anchor : a:cursor
    let l:empty = a:anchor[1:2] ==# a:cursor[1:2] && empty(getline(l:end[1]))
    return &selection !=# 'old' && &virtualedit !~# '\<all\>'
                \ && (l:empty || (&selection !=# 'exclusive'
                \ && l:end[2] > strlen(getline(l:end[1])))) ? "\n" : ''
endfunction

" 字节位置转成屏幕列范围：Tab/全角字符可能占多列。
function! s:VisualScreenSpan(pos, virtual) abort
    let l:text = getline(a:pos[1])
    let l:start = strdisplaywidth(strpart(l:text, 0, a:pos[2] - 1)) + 1
    let l:char = matchstr(strpart(l:text, a:pos[2] - 1), '.')
    if a:virtual
        return [l:start + a:pos[3], l:start + a:pos[3]]
    endif
    return [l:start, l:start + max([1, strdisplaywidth(l:char, l:start - 1)]) - 1]
endfunction

function! s:SliceScreenCols(text, left, right, pad) abort
    let l:result = ''
    let l:col = 1
    for l:char in split(a:text, '\zs')
        let l:width = strdisplaywidth(l:char, l:col - 1)
        let l:end = l:col + l:width - 1
        if l:end >= a:left && l:col <= a:right
            let l:result .= l:col >= a:left && l:end <= a:right
                        \ ? l:char : repeat(' ', min([l:end, a:right]) - max([l:col, a:left]) + 1)
        endif
        let l:col += l:width
        if l:col > a:right
            break
        endif
    endfor
    if a:pad && l:col <= a:right
        let l:result .= repeat(' ', a:right - max([l:col, a:left]) + 1)
    endif
    return l:result
endfunction

" 按字节列切片 [c1, c2]：c2 为字符首字节时包含该完整字符（多字节安全；
" col()/strlen 均为字节单位，且总是落在字符边界上）
function! s:SliceVisualCols(text, c1, c2) abort
    if a:c1 > strlen(a:text)
        return ''
    endif
    let l:tail = strpart(a:text, a:c2 - 1)
    let l:endlen = empty(l:tail) ? 0 : strlen(matchstr(l:tail, '.'))
    return strpart(a:text, a:c1 - 1, a:c2 - a:c1 + l:endlen)
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
