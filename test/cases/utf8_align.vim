" utf8_align：中文作者名不得造成日期/行号列错位（显示宽度对齐）
" fixture: 中文文件名.txt 两行均归因于 张三丰（显示宽度 6，补 6 空格）
" 布局: hash(10)+sp author(12 显示宽)+sp date(10)+sp num(%*d)
let s:bb = VimbTestBlameBufnr()
let s:lines = getbufline(s:bb, 1, '$')
call assert_equal(2, len(s:lines))

" 块首行（第 1 行）应有完整 hash/作者/日期
let s:head = s:lines[0]
call assert_true(s:head =~# '^\x\{10\} 张三丰', '第 1 行应为块首行且作者为张三丰')
" 作者列以显示宽度填充到 12：张三丰(显示宽 6) + 6 空格；旧 bug 按字节填充
" （9 字节 + 3 空格 = 显示 9），日期列会左移 3 列
" stridx 是字节位置，须用 strdisplaywidth(strpart()) 折算显示列
let s:bytepos = stridx(s:head, '2022-04-04')
call assert_equal(24, strdisplaywidth(strpart(s:head, 0, s:bytepos)),
            \ '日期列应从显示列 24 开始（10+1+12+1）；偏小说明作者列按字节填充错位')
" 行号列右对齐（number_width = max(4, …)，2 行文件 → 4 列宽）
call assert_true(s:head =~# ' \+\d\{1,4\}$' && strdisplaywidth(s:head) == 39,
            \ '行号应右对齐且整行显示宽度为 39: [' . s:head . ']')
" 第 2 行为同块合并行（无 hash/作者/日期）
call assert_true(s:lines[1] =~# '^ \{22\}', '第 2 行应为合并行只留行号列')
VimbTestFinish
qall!
