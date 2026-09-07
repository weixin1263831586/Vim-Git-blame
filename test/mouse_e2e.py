#!/usr/bin/env python3
"""mouse_e2e：真实鼠标事件端到端测试。

在 pty 中运行 vimb，向 Vim 发送 SGR 鼠标序列（双击/拖拽/单击），用
PATH 里的 xclip 替身记录系统剪贴板写入，断言：
  - 双击：原生选词 + 稳定后复制（第一次双击即生效），选区保持高亮
  - 拖拽：自动复制完整选区
  - blame 双击不误开 commit 面板；单击照常打开
  - commit 面板同样支持双击/拖拽复制
依赖：python3、vim；不需要真实 X（DISPLAY 由假 xclip 接管）。
"""
import os
import json
import re
import select
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pty_mouse import VimPty  # noqa: E402

VIMB = os.environ.get('VIMB', os.path.join(HERE, '..', 'vimb'))
FIXTURE = os.environ.get('VIMB_E2E_FIXTURE')
CLIPDIR = os.environ.get('VIMB_FAKE_CLIP_DIR', '/tmp/vimb-fake-clip')
LOG = '/tmp/vimb-e2e-mode.log'

PROBE = '/tmp/vimb-e2e-probe.vim'
with open(PROBE, 'w') as f:
    f.write(
        "func! Probe(timer)\n"
        "  let m = mode(1)\n"
        "  if index(['v', 'V', nr2char(22), 's', 'S', nr2char(19)], m) >= 0\n"
        "    let a = getpos('v')\n"
        "    let c = getpos('.')\n"
        "    let s = a[1] . ':' . a[2] . '-' . c[1] . ':' . c[2]\n"
        "  else\n"
        "    let s = line(\"'<\") . ':' . col(\"'<\") . '-'"
        " . line(\"'>\") . ':' . col(\"'>\")\n"
        "  endif\n"
        "  let rec = m . ' sel=' . s . ' reg=' . strtrans(substitute(@\", \"\\n\", '<NL>', 'g'))\n"
        "  let rec .= ' anchor=' . string(getpos('v')) . ' cursor=' . string(getpos('.'))\n"
        "  let rec .= ' commit_lines=' . len(getbufline(bufnr('\\[vimb-commit\\]'), 1, '$'))\n"
        "  let bl = getbufline(bufnr('\\[vimb-blame\\]'), 1)\n"
        "  let rec .= ' bl=' . (empty(bl) ? '' : strcharpart(bl[0], 0, 8))\n"
        "  if !exists('g:last_rec') || g:last_rec !=# rec\n"
        "    let g:last_rec = rec\n"
        "    let ts = strftime('%H:%M:%S') . ' ' . (len(split(reltimestr(reltime()), '\\.')) < 2 ? '0' : strpart(split(reltimestr(reltime()), '\\.')[1], 0, 3))\n"
        "    call writefile([ts . ' ' . rec], '" + LOG + "', 'a')\n"
        "  endif\n"
        "endfunc\n"
        "set nomore\n"
        "let g:probe_timer = timer_start(30, 'Probe', {'repeat': -1})\n")

failures = []
checks = 0


def check(name, cond, detail=''):
    global checks
    checks += 1
    if cond:
        print('PASS %s' % name)
    else:
        print('FAIL %s  %s' % (name, detail))
        failures.append(name)


def read_log():
    try:
        with open(LOG, errors='replace') as f:
            return [l.rstrip('\n') for l in f.readlines()]
    except OSError:
        return []


def strip_ts(line):
    """去掉探针写入的时间戳前缀（'17:35:01 651 v ...' → 'v ...'）。"""
    return re.sub(r'^\d{2}:\d{2}:\d{2} \d+ ', '', line)


def clip(selection='clipboard'):
    try:
        with open(os.path.join(CLIPDIR, selection)) as f:
            return f.read()
    except OSError:
        return None


def pump(vp, seconds):
    """固定墙钟时间持续排空 pty。

    不能用 drain()：vimb 的 60ms 观察定时器会让 vim 每几十毫秒输出一次
    光标开关序列，drain 的静默判定永远无法满足，会把 pump 拖到内部 10s
    超时，彻底打乱后续鼠标事件的发送时机。
    """
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        r, _, _ = select.select([vp.master], [], [], 0.02)
        if r:
            try:
                os.read(vp.master, 65536)
            except OSError:
                break


def git_hash():
    out = subprocess.run(['git', '-C', FIXTURE, 'rev-parse', 'HEAD'],
                         capture_output=True, timeout=10)
    return out.stdout.decode().strip()


def main():
    for p in [LOG] + [os.path.join(CLIPDIR, s)
                      for s in ('clipboard', 'primary')]:
        try:
            os.unlink(p)
        except OSError:
            pass

    full_hash = git_hash()
    short_hash = full_hash[:10]

    env = {
        'VIMB_TEST_CMDS': 'source ' + PROBE + "\nsource "
                          + os.path.join(HERE, 'pty_helper.vim'),
        'DISPLAY': ':99',
        'WAYLAND_DISPLAY': '',
    }
    vp = VimPty([VIMB, os.path.join(FIXTURE, 'code.txt')], env=env)
    try:
        run(vp, full_hash, short_hash)
    finally:
        vp.quit()

    print('=== mouse_e2e: %d 通过, %d 失败 ===' % (checks - len(failures),
                                              len(failures)))
    if failures:
        print('失败: %s' % ' '.join(failures))
        return 1
    return 0


def run(vp, full_hash, short_hash):
    vp.drain(2.5)
    # 等 blame 内容就绪（异步 job）
    deadline = time.time() + 20
    blame_line = None
    while time.time() < deadline:
        vp.enter("call writefile([getbufline(bufnr('\\[vimb-blame\\]'), 1)[0]],"
                 " '/tmp/vimb-e2e-blame.txt')")
        time.sleep(0.4)
        try:
            with open('/tmp/vimb-e2e-blame.txt') as f:
                blame_line = f.read().strip()
        except OSError:
            blame_line = ''
        if re.match(r'^[0-9a-f]{10} ', blame_line or ''):
            break
    if not (blame_line or '').startswith(short_hash):
        vp.enter('redir! > /tmp/vimb-e2e-msgs.txt | silent messages | redir END')
        time.sleep(0.5)
        try:
            with open('/tmp/vimb-e2e-msgs.txt') as f:
                print('---- vim messages ----')
                print(f.read()[-2000:])
        except OSError:
            pass
    check('blame_loaded', bool(blame_line and
                               blame_line.startswith(short_hash)),
          'blame 行: %r' % blame_line)

    # 窗口布局：source 右侧带行号列，blame 左侧无行号
    vp.enter('call VimbPtyWins("/tmp/vimb-e2e-wins.txt")')
    time.sleep(0.6)
    wins = {}
    with open('/tmp/vimb-e2e-wins.txt') as f:
        for line in f:
            m = re.match(r'winid=(\d+) buf=(\S+) wincol=(\d+) winrow=(\d+)'
                         r' width=(\d+) height=(\d+) topline=(\d+)', line)
            if m:
                wins[m.group(2)] = dict(winid=int(m.group(1)),
                                        wincol=int(m.group(3)),
                                        winrow=int(m.group(4)),
                                        width=int(m.group(5)),
                                        height=int(m.group(6)),
                                        topline=int(m.group(7)))
    src = wins.get(os.path.join(FIXTURE, 'code.txt'))
    blame = wins.get('[vimb-blame]')
    check('layout', bool(src and blame), 'windows: %r' % wins)
    if not (src and blame):
        return

    # 校准源窗口文本起始屏幕列：点一下读光标列
    probe_col = src['wincol'] + 7
    vp.click(probe_col, src['winrow'])
    time.sleep(0.3)
    vp.enter('call writefile([col(".")], "/tmp/vimb-e2e-cal.txt")')
    time.sleep(0.5)
    with open('/tmp/vimb-e2e-cal.txt') as f:
        bufcol = int(f.read().strip())
    textcol = probe_col - bufcol + 1
    time.sleep(0.6)  # 与后续双击拉开距离，避免影响 multi-click 判定

    # --- 场景 1：源窗口第一次双击 one（1:7-1:9） ---
    vp.double_click(textcol + 6, src['winrow'])
    time.sleep(0.8)
    check('double_first_clipboard', clip() == 'one',
          'clipboard=%r' % clip())
    check('double_first_primary', clip('primary') == 'one',
          'primary=%r' % clip('primary'))
    check('double_first_visual', any(strip_ts(l).startswith('v sel=1:7-1:9')
                                     for l in read_log()),
          'log=%r' % read_log()[-6:])

    # --- 场景 2：不按 Esc，直接双击另一行 three（锚点重置，2:7-2:11） ---
    vp.double_click(textcol + 6, src['winrow'] + 1)
    time.sleep(0.8)
    check('double_second_clipboard', clip() == 'three',
          'clipboard=%r' % clip())
    check('double_second_visual', any(strip_ts(l).startswith('v sel=2:7-2:11')
                                      for l in read_log()),
          'log=%r' % read_log()[-6:])
    vp.key('\x1b')
    time.sleep(0.3)

    # --- 场景 3：源窗口拖拽 1:1 -> 2:11 ---
    vp.drag(textcol, src['winrow'], textcol + 10, src['winrow'] + 1)
    time.sleep(0.8)
    expected = 'alpha one alpha two\nalpha three'
    check('drag_clipboard', clip() == expected, 'clipboard=%r' % clip())
    check('drag_visual', any(strip_ts(l).startswith('v sel=1:1-2:11')
                             for l in read_log()),
          'log=%r' % read_log()[-8:])
    vp.key('\x1b')
    time.sleep(0.3)

    # --- 场景 4：blame 双击 hash（不误开 commit 面板） ---
    vp.double_click(4, blame['winrow'])
    time.sleep(1.0)
    check('blame_double_clipboard', clip() == short_hash,
          'clipboard=%r 期望 %r' % (clip(), short_hash))
    check('blame_double_visual', any(strip_ts(l).startswith('v sel=1:1-1:10')
                                     for l in read_log()),
          'log=%r' % read_log()[-6:])
    vp.enter('call VimbPtyWins("/tmp/vimb-e2e-wins.txt")')
    time.sleep(0.6)
    has_commit = any('vimb-commit' in line
                     for line in open('/tmp/vimb-e2e-wins.txt'))
    check('blame_double_no_commit_panel', not has_commit,
          '双击后不应打开 commit 面板')
    vp.key('\x1b')
    time.sleep(0.3)

    # --- 场景 5：blame 单击打开 commit 面板，面板内双击完整 hash ---
    vp.click(4, blame['winrow'] + 1)
    time.sleep(1.0)
    vp.enter('call VimbPtyWins("/tmp/vimb-e2e-wins.txt")')
    time.sleep(0.6)
    commit = None
    for line in open('/tmp/vimb-e2e-wins.txt'):
        m = re.match(r'winid=(\d+) buf=\[vimb-commit\] wincol=(\d+) winrow=(\d+)'
                     r' width=(\d+) height=(\d+) topline=(\d+)', line)
        if m:
            commit = dict(wincol=int(m.group(2)), winrow=int(m.group(3)),
                          topline=int(m.group(6)))
    check('commit_panel_open', bool(commit), '单击后应打开 commit 面板')
    if commit:
        # commit 第 1 行 "vimb commit <40位hash>"：hash 从第 13 列开始
        vp.double_click(commit['wincol'] + 14, commit['winrow'])
        time.sleep(0.8)
        check('commit_double_clipboard', clip() == full_hash,
              'clipboard=%r 期望 %r' % (clip(), full_hash))
        check('commit_double_visual',
              any(strip_ts(l).startswith('v sel=1:13-1:52') for l in read_log()),
              'log=%r' % read_log()[-6:])
        vp.key('\x1b')
        time.sleep(0.2)
        # commit 标题中的真实拖拽，最后坐标只在 release 中上报。
        vp.drag(commit['wincol'], commit['winrow'],
                commit['wincol'] + 10, commit['winrow'])
        pump(vp, 0.5)
        check('commit_drag_clipboard', clip() == 'vimb commit', repr(clip()))
        check('commit_drag_keeps_visual',
              strip_ts(read_log()[-1]).startswith('v sel=1:1-1:11'),
              repr(read_log()[-1:]))
        vp.key('\x1b')
        pump(vp, 0.2)
        # q 关闭场景 5 打开的 commit 面板，恢复 blame+source 两窗布局
        vp.key('q')
        time.sleep(0.6)

    # --- 场景 6：blame 双击后按住拖拽扩展选区（单击定时器必须让位） ---
    # 双击 hash 后不松手继续拖到第 22 列再释放：定时器在 Visual 模式下
    # 触发时应放弃打开面板，最终复制扩展后的完整选区。
    vp.mouse('press', 4, blame['winrow'])
    time.sleep(0.06)
    vp.mouse('release', 4, blame['winrow'])
    time.sleep(0.12)
    vp.mouse('press', 4, blame['winrow'])
    time.sleep(0.06)
    for c in range(6, 23):
        vp.mouse('drag', c, blame['winrow'])
        time.sleep(0.02)
    vp.mouse('release', 22, blame['winrow'])
    time.sleep(1.0)
    vp.enter('call VimbPtyWins("/tmp/vimb-e2e-wins.txt")')
    time.sleep(0.6)
    wins_txt = open('/tmp/vimb-e2e-wins.txt').read()
    check('dbl_drag_no_commit_panel', 'vimb-commit' not in wins_txt,
          '双击拖拽期间不应打开 commit 面板: %r' % wins_txt)
    check('dbl_drag_no_bogus_buffers',
          all(l.count('buf=') <= 1 for l in wins_txt.splitlines())
          and '[vimb-blame]' in wins_txt, '布局异常: %r' % wins_txt)
    # 拖拽扩展按 vim 原生 word-wise 语义：选区从 1:1 扩展过 1:10
    sel_ok = any(re.match(r'v sel=1:1-1:(1[1-9]|2[0-9]|3[0-9])', strip_ts(l))
                 for l in read_log())
    check('dbl_drag_visual_extended', sel_ok,
          'log=%r' % read_log()[-8:])
    c6 = clip()
    check('dbl_drag_clipboard_extended',
          bool(c6) and len(c6) > 10 and blame_line.startswith(c6),
          'clipboard=%r blame_line=%r' % (c6, blame_line))

    # --- 场景 7：:w 后立即双击，异步 blame 刷新不得打断选区（延迟应用）---
    # slowbin/git 把 blame 请求延迟 ~0.9s，保证回调落在双击选区保持期间。
    # 注意先切回源窗口：场景 6 的拖拽把焦点留在了 blame 窗口。
    vp.enter("call writefile(['R7'], '%s', 'a')" % LOG)
    vp.enter('call win_gotoid(%d)' % src['winid'])
    vp.enter('call setline(1, "zeta one alpha two")')
    vp.enter('w')
    vp.enter('call win_gotoid(%d)' % blame['winid'])
    vp.double_click(4, blame['winrow'])
    # 保持选区并持续读取：长 sleep 不读 pty 会把 vim 阻塞在 write 上，
    # 冻结 job/timer 回调，测不出真实竞态。drain 的静默判定在持续输出下
    # 会把循环拖到远超 2.4s——选区保持多久都不该被应用打断，这反而是
    # 额外覆盖（曾因“10 秒强制应用保险丝”在此翻车，已移除）。
    pump(vp, 2.4)
    check('race_copy_clipboard', clip() == short_hash,
          'clipboard=%r 期望 %r' % (clip(), short_hash))
    # 边界标记必须在 Esc 之前写入日志：enter() 的 :call 与紧随的 Esc 走
    # 同一输入流，vim 先执行 writefile 再处理 Esc，因此 PRE_ESC 之前的
    # WORKTREE 一定是“选区还在保持期间”就被应用了（bug）；Esc 后延迟
    # 应用（~120ms tick）落在 PRE_ESC 之后，不会被误判 early。
    vp.enter("call writefile(['PRE_ESC'], '%s', 'a')" % LOG)
    vp.key('\x1b')
    pump(vp, 1.0)
    race = read_log()
    r7 = race.index('R7') + 1 if 'R7' in race else 0
    esc = race.index('PRE_ESC') if 'PRE_ESC' in race else len(race)
    held = [i for i, l in enumerate(race)
            if r7 <= i < esc and strip_ts(l).startswith('v ')]
    early = [i for i, l in enumerate(race)
             if r7 <= i < esc and ' bl=WORKTREE' in l]
    late = [i for i, l in enumerate(race)
            if i > esc and ' bl=WORKTREE' in l]
    check('race_deferred_apply',
          bool(held) and not early and bool(late),
          '选区保持期间不应应用刷新、Esc 后应应用: held=%r early=%r '
          'late=%r esc=%d tail=%r' % (held, early, late, esc, race[-6:]))

    # --- 场景 8：快速连续复制，慢的旧任务不能在最后覆盖新的文本。---
    vp.enter('VimbCopyText slow-clipboard-write')
    pump(vp, 0.1)
    vp.enter('VimbCopyText latest-clipboard-write')
    pump(vp, 1.1)
    for selection in ('clipboard', 'primary'):
        check('ordered_' + selection, clip(selection) == 'latest-clipboard-write',
              repr(clip(selection)))

    # --- 场景 9：Select 模式（用户 :behave ms 配置）也保留原生选词。---
    vp.enter('set selectmode=mouse selection=exclusive')
    coords = vp.state('select-coords', ['json_encode(screenpos(%d, 1, 6))' % src['winid']])
    wordpos = json.loads(coords[0])
    vp.double_click(wordpos['col'], wordpos['row'])
    pump(vp, 0.6)
    check('select_mode_word', clip() == 'one', repr(clip()))
    check('select_mode_kept', strip_ts(read_log()[-1]).startswith('s '),
          repr(read_log()[-1:]))
    vp.key('\x1b')
    vp.enter('set selectmode= selection=inclusive')
    pump(vp, 0.5)

    # --- 场景 10：加载 commit 时选择标题，结果必须等 Esc 后才填入。---
    vp.enter('call win_gotoid(%d)' % src['winid'])
    vp.enter('call cursor(2, 1)')
    vp.key('\rf')  # 切换到未缓存的“全部文件”范围，确保本次真正异步加载。
    pump(vp, 0.25)
    # 与场景 5 相同的布局；slow git 的 show 延迟（2.5s）保证回调必然
    # 落在双击选区保持期间（高负载下输入延迟也不会抢先应用）。
    vp.double_click(commit['wincol'] + 14, commit['winrow'])
    pump(vp, 3.2)
    held_commit = strip_ts(read_log()[-1])
    check('commit_loading_selection_kept', held_commit.startswith('v sel=1:13-1:52')
          and 'commit_lines=4' in held_commit, held_commit)
    check('commit_loading_copy', clip() == full_hash, repr(clip()))
    vp.key('\x1b')
    # 内容应用时机受负载影响（回调 + 120ms 延迟 tick），轮询而非固定等待。
    deadline = time.time() + 5
    loaded = None
    while time.time() < deadline:
        pump(vp, 0.2)
        m2 = re.search(r'commit_lines=(\d+)', strip_ts(read_log()[-1]))
        if m2 and int(m2.group(1)) > 4:
            loaded = m2
            break
    check('commit_loading_applied_after_escape', bool(loaded),
          repr(read_log()[-1:]))

    # --- 场景 11：原生三击选行，保留换行及行寄存器类型。---
    title = vp.state('commit-title', ["getline(1)"])[0]
    for _ in range(3):
        vp.click(commit['wincol'] + 3, commit['winrow'])
        time.sleep(0.06)
    pump(vp, 0.5)
    check('triple_click_line', clip() == title + '\n', repr(clip()))
    check('triple_click_visual', strip_ts(read_log()[-1]).startswith('V '),
          repr(read_log()[-1:]))
    vp.key('\x1b')
    pump(vp, 0.3)
    regtype = vp.state('line-register-type', ["getregtype('\"')"])
    check('triple_click_register_type', regtype == ['V'], repr(regtype))
    vp.quit()


if __name__ == '__main__':
    sys.exit(main())
