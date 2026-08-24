" 文件历史默认/环境限制应下推给 Git，避免一次渲染无限记录。
let s:fw = VimbTestFileWin()
call VimbTestKey(s:fw, 'gh')
VimbWait
let s:hb = bufnr('\[vimb-history\]')
let s:records = filter(copy(getbufvar(s:hb, 'vimb_history_records', [])),
            \ '!empty(v:val)')
call assert_equal(1, len(s:records), 'VIMB_HISTORY_LIMIT=1 应只读取一条记录')
call assert_match('deep 3', get(s:records[0], 'summary', ''),
            \ '受限历史应保留最新提交')
VimbTestFinish
qall!
