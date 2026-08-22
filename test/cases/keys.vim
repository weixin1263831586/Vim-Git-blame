" keys：i 轻量信息 popup、y 复制 SHA、o 的 URL 构造
let s:fw = VimbTestFileWin()
let s:records = VimbTestRecords()

" y：在源窗口第 2 行复制 Bob 的 commit SHA
call win_execute(s:fw, 'normal! 2G')
call VimbTestKey(s:fw, 'y')
call assert_equal(s:records[1].hash, @", 'y 应复制完整 SHA 到未命名寄存器')

" y：blame 窗口行同样可用
let s:bw = VimbTestBufWin('\[vimb-blame\]')
call win_execute(s:bw, 'normal! 1G')
call VimbTestKey(s:bw, 'y')
call assert_equal(s:records[0].hash, @", 'blame 窗口 y 应复制该行 SHA')

" y：WORKTREE 行提示且不覆盖寄存器
call win_execute(s:fw, 'normal! 6G')
call VimbTestKey(s:fw, 'y')
call assert_equal(s:records[0].hash, @", 'WORKTREE 行 y 不应改变寄存器')

" i：源窗口第 2 行应弹出 popup（记录经纯内存生成）
call win_execute(s:fw, 'normal! 2G')
redir! > /tmp/vimb_keys_i.txt
call VimbTestKey(s:fw, 'i')
redir END
" popup 模式不产生错误即认为成功；无 popup 特性时退化为 echo
if exists('*popup_atcursor')
    let s:popups = popup_list()
    call assert_true(len(s:popups) > 0, 'i 应弹出 popup')
    for s:pid in s:popups
        call popup_close(s:pid)
    endfor
endif

" o：URL 构造（fixture 远端为 git@github.com:example/vimb-test.git）
redir! > /tmp/vimb_keys_url.txt
execute 'VimbCommitURL ' . s:records[1].hash
redir END
call assert_equal('https://github.com/example/vimb-test/commit/'
            \ . s:records[1].hash, join(readfile('/tmp/vimb_keys_url.txt'), ''),
            \ 'GitHub SSH 远端应构造正确的 commit URL')
VimbTestFinish
qall!
