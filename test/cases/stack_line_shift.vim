" stack_line_shift：父版本头部插入后，Tab 必须映射到父版本正确行
" fixture: base=[a,target,z] → head=[new,a,target2,z]
" 第 3 行 target2 归因 head 提交；父版本中 target 在第 2 行（不是第 3 行！）
let s:fw = VimbTestFileWin()
call win_execute(s:fw, 'normal! 3G')
call VimbTestKey(s:fw, '\<Tab>')
VimbWait
sleep 200m
VimbWait
let s:recs = VimbTestRecords()
call assert_equal(3, len(s:recs), '父版本应为 3 行')
" 关键断言：入栈后源窗口第“当前行”的内容必须是 target（修改前），
" 而不是 z（旧行号 3 的错误结果）
let s:line = VimbTestFileLine()
call assert_equal('target', get(getbufline(winbufnr(s:fw), s:line, s:line), 0, ''),
            \ 'Tab 后必须定位到父版本的 target 行，而不是同行的 z')
VimbTestFinish
qall!
