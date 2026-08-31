" vimb pty 探测辅助：窗口布局 / 状态 dump
func! VimbPtyWins(path)
  let out = []
  for w in filter(getwininfo(), 'v:val.tabnr==tabpagenr()')
    let b = bufname(w.bufnr)
    call add(out, printf('winid=%d buf=%s wincol=%d winrow=%d width=%d height=%d topline=%d',
          \ w.winid, empty(b) ? '?' : b, w.wincol, w.winrow, w.width, w.height, w.topline))
  endfor
  call writefile(out, a:path)
endfunc

func! VimbPtyTextCol(path, winid)
  " 返回指定窗口第 1 行文本 buffer 第 1 列对应的屏幕列
  let w = getwininfo(a:winid)[0]
  let offset = 1
  if gettabwinvar(w.tabnr, w.winnr, '&number')
    let offset = strlen(line('$', a:winid)) + 2
  endif
  call writefile(['textcol=' . (w.wincol + offset - 1)], a:path)
endfunc
