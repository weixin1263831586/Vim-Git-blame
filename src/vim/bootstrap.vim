function! s:Help() abort
    if s:WindowMatches(s:history_winid, s:history_bufnr)
                \ && win_getid() == s:history_winid
        call s:Info('history: Enter 查看 commit；Tab 进入该 revision；y 复制 SHA；o 浏览器；gh/gl 切换；q 关闭')
    elseif s:CommitWin()
        call s:Info('commit: f 仅此文件/全部文件；i 信息；y 复制 SHA；o 浏览器打开；gh 文件历史；gl 行历史；q/Backspace/Ctrl-O 返回；gb 关闭全部')
    elseif win_getid() == s:BlameWin()
        call s:Info('blame: Enter 查看 commit；Tab 追溯历史；BS 返回；i 信息；y 复制 SHA；o 浏览器；gh/gl 历史；r 刷新；q 关闭')
    else
        call s:Info('文件: Enter 查看 commit；Tab/BS 历史；i 信息；y 复制 SHA；o 浏览器；gh 文件历史；gl 行历史；gb 显示/隐藏 blame；F5 刷新')
    endif
endfunction

command! -bar VimbToggle call <SID>Toggle()
command! -bar VimbRefresh call <SID>Refresh(1)
command! -bar VimbBack call <SID>CloseCommit(1)
command! -bar VimbHelp call <SID>Help()

" win_execute() 需要字符串命令，而 expand('<SID>') 在部分环境下返回空，
" 不能在运行期拼接 <SNR> 前缀。这些命令在定义期完成 <SID> 展开，供
" win_execute() 间接调用脚本局部函数。
command! -bar VimbHighlightCommit call <SID>HighlightCommit()
command! -bar VimbResizeBlame call <SID>ResizeBlame()
command! -bar VimbPopulatePendingBlame call <SID>PopulatePendingBlame()
command! -bar VimbRestoreFileMaps call <SID>RestoreActiveFileMapsHere()
command! -bar VimbAlignBlame call <SID>AlignBlameToSource()
command! -nargs=1 VimbCopyText call <SID>CopyText(<q-args>)
command! -bar VimbVisualCopyNow call <SID>VisualCopyNow()
command! -bar VimbVisualText let g:vimb_visual_text = <SID>VisualSelectionText()

" 内部测试钩子：等待所有后台 Git job 结束（带超时），无 job 时立即返回。
function! s:WaitJobs() abort
    let l:rounds = 0
    while !empty(s:jobs) && l:rounds < 1000
        sleep 10m
        let l:rounds += 1
    endwhile
endfunction
command! -bar VimbWait call <SID>WaitJobs()

if resolve(expand('%:p')) !=# resolve(s:file_path)
    call s:Error('启动文件与请求文件不一致，已中止 blame 初始化')
else
    setlocal number
    nnoremap <buffer> <silent> gb :call <SID>Toggle()<CR>
    nnoremap <buffer> <silent> ? :call <SID>Help()<CR>
    " 内部测试钩子：VIMB_NO_AUTO_OPEN=1 时不自动打开 blame
    if $VIMB_NO_AUTO_OPEN !=# '1'
        call s:OpenBlame()
    endif
endif

" 内部测试钩子：VIMB_TEST_CMDS 每行一条 Ex 命令，在初始化完成后执行
" （仅用于回归测试，普通使用无需关心）。
if $VIMB_TEST_CMDS !=# ''
    for s:test_cmd in split($VIMB_TEST_CMDS, "\n", 1)
        execute s:test_cmd
    endfor
endif
