" ---- 视觉：per-commit 配色块 + commit 年龄热力 -----------------------------
" 年龄分档：相对当前时间的实际代码年龄
"   0: 30 天内(亮绿)  1: 1 年内(绿)  2: 3 年内(蓝)  3: 更早(灰)
function! s:AgeBucket(author_time, now) abort
    if a:author_time <= 0 || a:now <= 0
        return 3
    endif
    let l:days = max([0, (a:now - a:author_time) / 86400])
    if l:days <= 30
        return 0
    elseif l:days <= 365
        return 1
    elseif l:days <= 1095
        return 2
    endif
    return 3
endfunction

function! s:DefineBlameSyntax(records) abort
    " 年龄热力（hash 列前景色）任何终端都开；per-commit 色块需要 256 色
    if !has('syntax')
        return
    endif
    let l:now = localtime()
    syntax clear
    unlet! b:current_syntax
    if !(has('gui_running') || &t_Co >= 256)
        " 低色彩终端：仅年龄热力
        for l:bucket in range(4)
            let l:pat = s:AgePattern(a:records, l:now, l:bucket)
            if !empty(l:pat)
                execute 'syntax match VimbAge' . l:bucket . ' /\%(' . l:pat
                            \ . '\)\%10c/ containedin=ALL'
            endif
        endfor
        return
    endif
    " 相邻 commit 块循环 4 色：每个连续块只创建一个 region，而不是逐行
    " 创建。大文件的语法项数量由 O(lines) 降为 O(commit blocks)。
    let l:block = 0
    let l:last_hash = ''
    let l:block_start = 0
    let l:index = 0
    for l:record in a:records
        let l:index += 1
        if l:record.hash !=# l:last_hash
            if l:block_start > 0
                call s:DefineBlameBlock(l:block, l:block_start, l:index - 1)
            endif
            let l:block += 1
            let l:last_hash = l:record.hash
            let l:block_start = l:index
            " 块首行 hash 列按实际年龄着色（region 只盖底色）
            let l:bucket = s:AgeBucket(get(l:record, 'author_time', 0), l:now)
            let l:age_pat = '\%' . l:index . 'l\%1c\S\+\%10c'
            execute 'syntax match VimbAge' . l:bucket . ' /' . l:age_pat . '/'
        endif
    endfor
    if l:block_start > 0
        call s:DefineBlameBlock(l:block, l:block_start, l:index)
    endif
endfunction

function! s:DefineBlameBlock(block, first, last) abort
    let l:group = 'VimbC' . (a:block % 4)
    execute 'syntax region ' . l:group . ' start=/\%' . a:first
                \ . 'l\%^/ end=/\%' . a:last . 'l\%$/'
endfunction

" 生成某年龄档所有块首行 hash 列的匹配模式（低色彩终端用）
function! s:AgePattern(records, newest, bucket) abort
    let l:parts = []
    let l:last_hash = ''
    let l:index = 0
    for l:record in a:records
        if l:record.hash !=# l:last_hash
            let l:last_hash = l:record.hash
            if s:AgeBucket(get(l:record, 'author_time', 0), a:newest) ==# a:bucket
                call add(l:parts, '\%' . (l:index + 1) . 'l\%1c\S\+\%10c')
            endif
        endif
        let l:index += 1
    endfor
    return join(l:parts, '\|')
endfunction

