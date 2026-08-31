#!/usr/bin/env python3
"""mouse_e2e：真实鼠标事件端到端测试。

在 pty 中运行 vimb，向 Vim 发送 SGR 鼠标序列（双击/拖拽/单击），用
PATH 里的 xclip 替身记录系统剪贴板写入，断言：
  - 双击：原生选词 + 释放复制（第一次双击即生效），选区保持高亮
  - 拖拽：释放自动复制完整选区
  - blame 双击不误开 commit 面板；单击照常打开
  - commit 面板同样支持双击/拖拽复制
依赖：python3、vim；不需要真实 X（DISPLAY 由假 xclip 接管）。
"""
import os
import re
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
    f.write('''
func! Probe(timer)
  let m = mode(1)
  let s = line("'<") . ':' . col("'<") . '-' . line("'>") . ':' . col("'>")
  let rec = m . ' sel=' . s . ' reg=' . strtrans(substitute(@", "\\n", '<NL>', 'g'))
  if !exists('g:last_rec') || g:last_rec !=# rec
    let g:last_rec = rec
    call writefile([rec], '%s', 'a')
  endif
endfunc
set nomore
let g:probe_timer = timer_start(30, 'Probe', {'repeat': -1})
''' % LOG)

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
        with open(LOG) as f:
            return [l.rstrip('\n') for l in f.readlines()]
    except OSError:
        return []


def clip(selection='clipboard'):
    try:
        with open(os.path.join(CLIPDIR, selection)) as f:
            return f.read()
    except OSError:
        return None


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
    check('double_first_visual', any(l.startswith('v sel=1:7-1:9')
                                     for l in read_log()),
          'log=%r' % read_log()[-6:])
    vp.key('\x1b')
    time.sleep(0.3)

    # --- 场景 2：紧接着双击第 2 行 three（锚点重置，2:7-2:11） ---
    vp.double_click(textcol + 6, src['winrow'] + 1)
    time.sleep(0.8)
    check('double_second_clipboard', clip() == 'three',
          'clipboard=%r' % clip())
    check('double_second_visual', any(l.startswith('v sel=2:7-2:11')
                                      for l in read_log()),
          'log=%r' % read_log()[-6:])
    vp.key('\x1b')
    time.sleep(0.3)

    # --- 场景 3：源窗口拖拽 1:1 -> 2:11 ---
    vp.drag(textcol, src['winrow'], textcol + 10, src['winrow'] + 1)
    time.sleep(0.8)
    expected = 'alpha one alpha two\nalpha three'
    check('drag_clipboard', clip() == expected, 'clipboard=%r' % clip())
    check('drag_visual', any(l.startswith('v sel=1:1-2:11')
                             for l in read_log()),
          'log=%r' % read_log()[-8:])
    vp.key('\x1b')
    time.sleep(0.3)

    # --- 场景 4：blame 双击 hash（不误开 commit 面板） ---
    vp.double_click(4, blame['winrow'])
    time.sleep(1.0)
    check('blame_double_clipboard', clip() == short_hash,
          'clipboard=%r 期望 %r' % (clip(), short_hash))
    check('blame_double_visual', any(l.startswith('v sel=1:1-1:10')
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
              any(l.startswith('v sel=1:13-1:52') for l in read_log()),
              'log=%r' % read_log()[-6:])
        vp.key('\x1b')
        time.sleep(0.2)
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
    sel_ok = any(re.match(r'v sel=1:1-1:(1[1-9]|2[0-9]|3[0-9])', l)
                 for l in read_log())
    check('dbl_drag_visual_extended', sel_ok,
          'log=%r' % read_log()[-8:])
    c6 = clip()
    check('dbl_drag_clipboard_extended',
          bool(c6) and len(c6) > 10 and blame_line.startswith(c6),
          'clipboard=%r blame_line=%r' % (c6, blame_line))
    vp.quit()


if __name__ == '__main__':
    sys.exit(main())
