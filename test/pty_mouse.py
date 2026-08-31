#!/usr/bin/env python3
"""pty 鼠标事件注入器：在真实 pty 中运行 vim/vimb，发送 SGR 鼠标序列，
并轮询 vim 内部状态文件来观察选区/复制结果。

用法:
  import pty_mouse  (由 test/mouse_e2e.sh 调用)
  直接运行: python3 pty_mouse.py <workdir> <vimb> <file>
"""
import os
import pty
import select
import signal
import subprocess
import sys
import time

ROWS, COLS = 50, 120


class VimPty:
    def __init__(self, cmd, env=None, rows=ROWS, cols=COLS):
        self.master, slave = pty.openpty()
        import fcntl
        import struct
        import termios
        fcntl.ioctl(slave, termios.TIOCSWINSZ,
                    struct.pack('HHHH', rows, cols, 0, 0))
        self.env = dict(os.environ)
        self.env.update(env or {})
        self.env['TERM'] = 'xterm-256color'
        self.env.pop('TMUX', None)
        self.proc = subprocess.Popen(
            cmd, stdin=slave, stdout=slave, stderr=slave,
            env=self.env, close_fds=True, preexec_fn=os.setsid)
        os.close(slave)
        self.drain()

    def drain(self, wait=0.0, quiet=0.15):
        """读取输出直到静默 quiet 秒（防止首轮 select 早退漏数据）。"""
        if wait:
            time.sleep(wait)
        out = b''
        deadline = time.time() + 10
        last = time.time()
        while time.time() < deadline:
            r, _, _ = select.select([self.master], [], [], 0.05)
            if r:
                try:
                    chunk = os.read(self.master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                out += chunk
                last = time.time()
            elif time.time() - last >= quiet:
                break
        return out

    def send(self, data):
        os.write(self.master, data)

    def key(self, s):
        self.send(s.encode())

    def enter(self, cmd):
        self.send((':' + cmd + '\r').encode())

    def mouse(self, ev, col, row, button=0):
        code = {'press': 'M', 'release': 'm', 'drag': 'M'}[ev]
        if ev == 'drag':
            seq = '\x1b[<32;%d;%d%s' % (col, row, code)
        else:
            seq = '\x1b[<%d;%d;%d%s' % (button, col, row, code)
        self.send(seq.encode())

    def click(self, col, row, gap=0.05):
        self.mouse('press', col, row)
        time.sleep(gap)
        self.mouse('release', col, row)

    def double_click(self, col, row, gap=0.05, between=0.08):
        self.mouse('press', col, row)
        time.sleep(gap)
        self.mouse('release', col, row)
        time.sleep(between)
        self.mouse('press', col, row)
        time.sleep(gap)
        self.mouse('release', col, row)

    def drag(self, c1, r1, c2, r2, pause=0.15):
        self.mouse('press', c1, r1)
        time.sleep(pause)
        steps = 6
        # 故意不在终点发送 drag：真实终端可能合并高频 motion，
        # 最终坐标只出现在 release 里。Vim 内建 <LeftRelease> 必须有
        # 机会处理它，否则选区会错停在倒数第一个坐标。
        for i in range(1, steps):
            c = c1 + (c2 - c1) * i // steps
            r = r1 + (r2 - r1) * i // steps
            self.mouse('drag', c, r)
            time.sleep(0.03)
        self.mouse('release', c2, r2)

    def state(self, name, exprs, timeout=10):
        """在 vim 内执行表达式并写到 /tmp 文件，等待文件出现。"""
        path = '/tmp/vimb-pty-%s-%d.txt' % (name, os.getpid())
        try:
            os.unlink(path)
        except OSError:
            pass
        joined = ','.join(exprs)
        self.enter("call writefile([%s], '%s')" % (joined, path))
        deadline = time.time() + timeout
        while time.time() < deadline:
            self.drain(0.05)
            if os.path.exists(path):
                time.sleep(0.05)
                with open(path) as f:
                    return [l.rstrip('\n') for l in f.readlines()]
        return None

    def alive(self):
        return self.proc.poll() is None

    def quit(self):
        try:
            self.enter('qall!')
        except OSError:
            pass
        time.sleep(0.3)
        if self.alive():
            try:
                self.proc.send_signal(signal.SIGTERM)
            except OSError:
                pass
            time.sleep(0.5)
        if self.alive():
            try:
                os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
            except OSError:
                pass
        try:
            os.close(self.master)
        except OSError:
            pass


def win_geometry(vp, winid):
    lines = vp.state('win%d' % winid, [
        "string(getwininfo(%d)[0])" % winid])
    if not lines:
        return None
    import ast
    info = ast.literal_eval(lines[0])
    return info


def clipboard_out():
    try:
        out = subprocess.run(['xclip', '-selection', 'clipboard', '-out'],
                             capture_output=True, timeout=5)
        return out.stdout.decode('utf-8', 'replace') if out.returncode == 0 else None
    except Exception:
        return None


def primary_out():
    try:
        out = subprocess.run(['xclip', '-selection', 'primary', '-out'],
                             capture_output=True, timeout=5)
        return out.stdout.decode('utf-8', 'replace') if out.returncode == 0 else None
    except Exception:
        return None


def clipboard_in(text):
    subprocess.run(['xclip', '-selection', 'clipboard', '-in'],
                   input=text.encode(), timeout=5)
