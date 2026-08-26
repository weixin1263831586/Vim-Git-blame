" vimb internal Vim script. All auxiliary buffers are buftype=nofile.
scriptencoding utf-8

if &compatible
    set nocompatible
endif

set mouse=a
if exists('+ttymouse')
    set ttymouse=sgr
endif
set ttimeout
set ttimeoutlen=100

if has('gui_running') || &t_Co >= 256
    highlight default VimbCurrentLine cterm=bold ctermbg=201 ctermfg=0
                \ gui=bold guibg=#ff00ff guifg=#000000
    highlight default VimbSameCommit cterm=NONE ctermbg=236 gui=NONE guibg=#3a3f44
    " 相邻 commit 块循环使用的底色（低色彩终端不启用，见 DefineBlameSyntax）
    highlight default VimbC0 cterm=NONE ctermbg=233 gui=NONE guibg=#121212
    highlight default VimbC1 cterm=NONE ctermbg=235 gui=NONE guibg=#262626
    highlight default VimbC2 cterm=NONE ctermbg=238 gui=NONE guibg=#444444
    highlight default VimbC3 cterm=NONE ctermbg=240 gui=NONE guibg=#585858
else
    " TERM=xterm 等低色彩终端：256 色号码会被近似成灰色，改用 ANSI 原色
    highlight default VimbCurrentLine cterm=bold ctermbg=5 ctermfg=15
                \ gui=bold guibg=#ff00ff guifg=#000000
    highlight default VimbSameCommit cterm=NONE ctermbg=8 gui=NONE guibg=#3a3f44
endif
" commit 年龄热力：hash 列按提交新旧着色（ANSI 安全色，任何终端可用）
highlight default VimbAge0 ctermfg=10 guifg=#00d700
highlight default VimbAge1 ctermfg=2 guifg=#5faf00
highlight default VimbAge2 ctermfg=4 guifg=#0087af
highlight default VimbAge3 ctermfg=8 guifg=#808080
highlight default link VimbHash Comment

" blame 缓冲区会直接定义自己的 buffer-local 语法项，不改变用户全局的
" syntax on/off 状态。

let s:git_root = $VIMB_GIT_ROOT
let s:rel_path = $VIMB_REL_PATH
let s:file_path = $VIMB_FILE
let s:file_filetype = &l:filetype
let s:file_bufnr = bufnr('%')
let s:source_winid = win_getid()
" blame 历史栈：层 0 为工作区，Tab 入栈后为历史 commit 层。
" 每层 {'commit','path','bufnr','records','line','mtime'}
let s:stack = [{'commit': '', 'path': s:rel_path, 'bufnr': s:file_bufnr,
            \ 'records': [], 'line': 1, 'mtime': -1}]
let s:src_bufs = {}   " 'commit:path' → 历史版本 nofile 缓冲区号
let s:src_cache_order = []
let s:history_cache_depth = $VIMB_HISTORY_CACHE_DEPTH =~# '^\d\+$'
            \ ? max([1, str2nr($VIMB_HISTORY_CACHE_DEPTH)]) : 20
let s:history_limit = $VIMB_HISTORY_LIMIT =~# '^\d\+$'
            \ ? max([1, str2nr($VIMB_HISTORY_LIMIT)]) : 500
let s:blame_bufnr = -1
let s:blame_winid = -1
let s:commit_bufnr = -1
let s:commit_winid = -1
let s:active = 0
let s:syncing = 0
let s:refreshing = 0
let s:closing_blame = 0
let s:closing_commit = 0
let s:file_options = {}
let s:file_maps = {}
let s:return_view = {}
let s:pending_records = []
" Git 执行层：默认走 job_start() 异步；!has('job') 或 VIMB_SYNC=1 时同步。
let s:async = has('job') && $VIMB_SYNC !=# '1'
let s:jobs = {}
let s:job_seq = 0
let s:blame_gen = 0
let s:commit_gen = 0
let s:mouse_click_timer = -1
let s:commit_cache = {}
let s:commit_cache_order = []
let s:commit_cache_bytes = 0
let s:commit_cache_max_bytes = 5 * 1024 * 1024
let s:commit_cache_entry_max_bytes = 2 * 1024 * 1024
let s:trace_gen = 0
let s:trace_busy = 0

" Git 对非 ASCII / 特殊字符路径默认输出 C-style quoting（"\344\270..."），
" 统一加 -c core.quotePath=false 让 blame/diff/show 输出明文路径，
" 残余 quoting（控制字符、引号等）再由 DecodeGitQuotedPath 解码。
function! s:GitBase() abort
    return 'env LC_ALL=C git -c core.quotePath=false --no-pager -C '
                \ . shellescape(s:git_root)
endfunction

" 解码 Git C-style quoted 路径："\344\270\255" → UTF-8 明文
function! s:DecodeGitQuotedPath(path) abort
    if a:path !~# '^"'
        return a:path
    endif
    let l:raw = a:path[1 : -2]
    let l:out = ''
    let l:i = 0
    while l:i < len(l:raw)
        let l:ch = l:raw[l:i]
        if l:ch ==# '\' && l:i + 1 < len(l:raw)
            let l:n = l:raw[l:i + 1]
            if l:n =~# '[0-7]' && l:i + 3 < len(l:raw)
                        \ && l:raw[l:i + 2] =~# '[0-7]' && l:raw[l:i + 3] =~# '[0-7]'
                let l:out .= nr2char(str2nr(l:raw[l:i+1 : l:i+3], 8))
                let l:i += 4
                continue
            elseif l:n ==# 'n'
                let l:out .= "\n"
            elseif l:n ==# 't'
                let l:out .= "\t"
            else
                let l:out .= l:n
            endif
            let l:i += 2
        else
            let l:out .= l:ch
            let l:i += 1
        endif
    endwhile
    return l:out
endfunction

function! s:Error(message) abort
    echohl ErrorMsg
    echomsg 'vimb: ' . a:message
    echohl None
endfunction

function! s:Info(message) abort
    echohl ModeMsg
    echo 'vimb: ' . a:message
    echohl None
endfunction

function! s:WindowMatches(winid, bufnr) abort
    if a:winid <= 0
        return 0
    endif
    let l:info = getwininfo(a:winid)
    return len(l:info) == 1
                \ && l:info[0].tabnr == tabpagenr()
                \ && (a:bufnr <= 0 || l:info[0].bufnr == a:bufnr)
endfunction

function! s:WindowForBuffer(preferred, bufnr) abort
    if s:WindowMatches(a:preferred, a:bufnr)
        return a:preferred
    endif
    for l:info in getwininfo()
        if l:info.tabnr == tabpagenr() && l:info.bufnr == a:bufnr
            return l:info.winid
        endif
    endfor
    return 0
endfunction

" 源窗口锚定：blame 打开期间窗口内可能切换工作区文件/历史版本缓冲区，
" 因此以窗口 id 为锚，不按缓冲区反查。
function! s:SourceWin() abort
    if s:WindowMatches(s:source_winid, -1)
        return s:source_winid
    endif
    " 兜底：锚失效但真实文件缓冲区还显示在别的窗口
    let s:source_winid = s:WindowForBuffer(0, s:file_bufnr)
    return s:source_winid
endfunction

function! s:BlameWin() abort
    let s:blame_winid = s:WindowForBuffer(s:blame_winid, s:blame_bufnr)
    return s:blame_winid
endfunction

function! s:CommitWin() abort
    let s:commit_winid = s:WindowForBuffer(s:commit_winid, s:commit_bufnr)
    return s:commit_winid
endfunction

function! s:CaptureView(winid) abort
    let s:captured_view = {}
    if s:WindowMatches(a:winid, -1)
        call win_execute(a:winid, 'let s:captured_view = winsaveview()')
    endif
    return copy(s:captured_view)
endfunction

function! s:RestoreView(winid, view) abort
    if !empty(a:view) && s:WindowMatches(a:winid, -1)
        call win_execute(a:winid, 'call winrestview(' . string(a:view) . ')')
    endif
endfunction

" scrollbind 维护的是相对滚动偏移；窗口分割/缩放时两侧分别恢复 view，
" 容易把这个偏移固化成一行。以源窗口为准显式重置 blame 的 topline，
" 同时让两个窗口重新建立零偏移的 scrollbind 基准。
function! s:AlignBlameToSource() abort
    let l:fw = s:SourceWin()
    let l:bw = s:BlameWin()
    if !l:fw || !l:bw
        return
    endif
    let l:file_view = s:CaptureView(l:fw)
    let l:blame_view = s:CaptureView(l:bw)
    if empty(l:file_view) || empty(l:blame_view)
        return
    endif
    let l:line = get(l:file_view, 'lnum', 1)
    let l:blame_view.lnum = min([l:line, line('$', l:bw)])
    let l:blame_view.col = 0
    let l:blame_view.coladd = 0
    let l:blame_view.curswant = 0
    let l:blame_view.topline = get(l:file_view, 'topline', 1)
    let l:blame_view.topfill = 0
    call win_execute(l:fw, 'setlocal noscrollbind')
    call win_execute(l:bw, 'setlocal noscrollbind')
    call s:RestoreView(l:fw, l:file_view)
    call s:RestoreView(l:bw, l:blame_view)
    call win_execute(l:fw, 'setlocal scrollbind')
    call win_execute(l:bw, 'setlocal scrollbind')
    call win_execute(l:fw, 'syncbind')
endfunction

function! s:GitFailure(lines) abort
    let l:text = substitute(join(a:lines, ' '), '\s\+', ' ', 'g')
    return empty(l:text) ? 'Git 命令执行失败' : strpart(l:text, 0, 240)
endfunction
