" stack_utf8_rename：中文旧名.c → 新名.c，修改行 Tab 入栈跟随旧路径
let s:fw = VimbTestFileWin()
let s:orig_buf = winbufnr(s:fw)
call win_execute(s:fw, 'normal! 2G')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
sleep 200m
VimbWait
call assert_notequal(s:orig_buf, winbufnr(s:fw), '应入栈成功')
call assert_match('旧文件', bufname(winbufnr(s:fw)),
            \ '历史缓冲区应基于中文旧路径创建: ' . bufname(winbufnr(s:fw)))
let s:recs = VimbTestRecords()
call assert_equal(2, len(s:recs), '父版本（旧文件）应为 2 行')
let s:line = VimbTestFileLine()
call assert_equal('u line 2', get(getbufline(winbufnr(s:fw), s:line, s:line), 0, ''),
            \ '应定位到修改前的第 2 行内容')
VimbTestFinish
qall!
