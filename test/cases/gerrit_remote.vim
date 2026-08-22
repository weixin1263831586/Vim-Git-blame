" gerrit_remote：ssh://user@gerrit.example.com:29418/project 的 URL 构造
" （VimbCommitURL 使用仓库 origin；fixture 的 gerrit-repo 已设该形式远端）
" 本用例在 gerrit-repo 的 g.txt 上运行，取第 1 行 hash 构造 URL
let s:records = VimbTestRecords()
call assert_equal(2, len(s:records))
redir! > /tmp/vimb_gerrit_url.txt
try
    execute 'VimbCommitURL ' . s:records[0].hash
catch
    call writefile(['EXC=' . v:exception], $VIMB_TEST_OUT)
    qall!
endtry
redir END
let s:url = join(readfile('/tmp/vimb_gerrit_url.txt'), '')
call assert_true(match(s:url, 'gerrit\.example\.com/c/platform/frameworks/base/+/') >= 0,
            \ 'Gerrit SSH 远端应构造 /c/<project>/+/<sha>: ' . s:url)
call assert_false(match(s:url, '29418') >= 0, 'Web URL 不应带 SSH 端口')
VimbTestFinish
qall!
