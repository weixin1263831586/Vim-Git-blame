# vimb

一个小巧、可预期的 Vim Git blame 工作区。在 Vim 中打开任意已被 Git 跟踪的文件，左侧自动显示逐行 blame 信息（commit、作者、日期、行号），点击任意行即可查看该 commit 的完整详情，返回后光标位置原样恢复。

单个 Bash 脚本实现，除 `vim` 和 `git` 外无任何依赖。

## 功能

- 左侧 blame 栏逐行显示 commit 短哈希、作者、日期和行号，未提交的工作区改动标记为 `WORKTREE`
- blame 栏与文件窗口双向同步光标位置，`scrollbind` 联动滚动
- 当前行的 commit 自动高亮，同属一个 commit 的所有行一起标出
- 鼠标单击或 Enter 查看该行所属 commit 的完整信息（fuller 格式 + stat + patch）
- q / Backspace / Ctrl-O 从 commit 视图返回原文件，视图位置精确恢复
- `gb` 随时显示或隐藏 blame；保存文件后自动刷新，`r` / F5 手动刷新
- 未提交的工作区行不支持查看 commit，会明确提示
- 所有辅助缓冲区均为只读临时缓冲区（`buftype=nofile`），不会在磁盘留下任何文件
- 只打开命令行指定的文件，绝不加载其他缓冲区

## 安装

```bash
git clone git@github.com:weixin1263831586/vimb.git
install -m 755 vimb/vimb ~/.local/bin/vimb
```

要求 `~/.local/bin` 在 `PATH` 中。

## 使用

```bash
vimb <文件>
```

文件名以 `-` 开头时：

```bash
vimb -- <文件>
```

其他参数：

```bash
vimb -h          # 查看帮助
vimb --version   # 查看版本
```

## 快捷键

| 按键 | 位置 | 作用 |
| --- | --- | --- |
| 鼠标单击 / Enter | blame 栏 | 查看该行所属 commit |
| q / Backspace / Ctrl-O | commit 视图 | 返回原文件 |
| q / Ctrl-C | blame 栏 | 关闭 blame |
| gb | 任意位置 | 显示或隐藏 blame |
| r / F5 | blame 栏或文件 | 刷新 blame |
| ? | 任意位置 | 显示快捷键提示 |

## 工作方式

脚本先校验文件必须位于 Git 工作区内且已被跟踪，然后生成一段临时 Vim script（用后即删），在文件左侧打开一个 `buftype=nofile` 的 blame 缓冲区，底部按需打开 commit 详情缓冲区。blame 数据来自 `git blame --line-porcelain`，commit 详情来自 `git show --format=fuller --stat --patch`。

关闭 blame 后，文件的窗口选项（wrap、scrollbind）、缓冲区局部映射和视图位置都会恢复原状。

## 许可

供个人使用，未指定开源许可证。
