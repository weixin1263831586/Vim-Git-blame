" big：20000 行大文件，记录数与多 commit 分布
let s:records = VimbTestRecords()
call assert_equal(20000, len(s:records))
let s:hashes = {}
for s:r in s:records
    let s:hashes[s:r.hash] = 1
endfor
call assert_equal(2, len(s:hashes), '应有两个 commit 的行（初始 + 修改）')
call assert_equal('Carol Changer', s:records[4995].author, '第 4996 行应属于修改 commit')
VimbTestFinish
qall!
