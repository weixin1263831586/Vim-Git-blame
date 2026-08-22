" history_close_race：gh 后立即 q，晚到的异步回调不得报错
let s:fw = VimbTestFileWin()
redir! > /tmp/vimb_race.msg
call VimbTestKey(s:fw, 'gh')
" 不等加载完成，立即关闭
let s:hb = bufnr('\[vimb-history\]')
call assert_notequal(-1, s:hb)
let s:hw = bufwinid(s:hb)
call win_execute(s:hw, 'execute "normal q"')
sleep 300m
VimbWait
redir END
call assert_equal(-1, bufnr('\[vimb-history\]'), '历史面板应已关闭')
" 无 E 错误
let s:msgs = join(readfile('/tmp/vimb_race.msg', '', 0, 50), "\n")
call assert_false(match(s:msgs, 'E[0-9]\+:') >= 0, '关闭后回调不应报错')
VimbTestFinish
qall!
