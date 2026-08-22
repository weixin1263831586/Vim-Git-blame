# vimb

一个小巧、可预期的 Vim Git 代码历史追溯（Code Archaeology）工作区。一条命令 `vimb <文件>` 启动：左侧逐行 blame、双向光标同步、单击查看 commit patch，还能用 Tab 逐层向前追溯一行的历史来源，直到最初引入它的提交。

单个 Bash 脚本实现，除 `vim` 和 `git` 外无任何依赖。

## 功能

- 左侧 blame 栏逐行显示 commit 短哈希、作者、日期和行号，未提交的工作区改动标记为 `WORKTREE`
- blame 栏与文件窗口双向同步光标位置，`scrollbind` 联动滚动
- 当前行的 commit 自动高亮，同属一个 commit 的所有行一起标出
- 鼠标单击或 Enter 查看该行所属 commit 的完整信息（fuller 格式 + stat + patch）
- **Tab 向前追溯**：基于 `previous` 字段入栈显示历史版本文件，rename/移动过的代码自动跟随旧路径；Backspace 逐层返回，blame 栏显示当前深度（如 `vimb blame 2 层 @79583ef`）
- `gh` 文件历史（`git log --follow`，rename 后继续追溯）；`gl` 当前行历史（`git log -L`）
- `i` 轻量 commit 信息 popup（作者/日期/previous，纯内存零 Git 调用）
- `y` 复制完整 commit SHA（尽力同步系统剪贴板）
- `o` 在浏览器打开 commit（支持 GitHub / GitLab / Gitee / Bitbucket / Sourcehut / Gerrit）
- `f` 在 commit 面板切换 仅此文件 / 全部文件
- q / Backspace / Ctrl-O 从 commit 视图返回原文件，视图位置精确恢复
- `gb` 随时显示或隐藏 blame；保存文件后自动刷新，`r` / F5 手动刷新
- Git 调用异步执行（`job_start()`，Vim 8+ 自带），大文件 blame 与大 commit patch 不阻塞 UI；无 `+job` 特性时自动退回同步
- blame 解析结果建 hash→行号索引，同 commit 高亮为 O(1) 查找；commit 渲染结果带缓存
- 未提交的工作区行不支持查看 commit，会明确提示
- 所有辅助缓冲区均为只读临时缓冲区（`buftype=nofile`），不会在磁盘留下任何文件
- 只打开命令行指定的文件，绝不加载其他缓冲区

## 安装

一键安装（依赖 `curl` 或 `wget`）：

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/weixin1263831586/Vim-Git-blame/main/install.sh | sh
```

或手动安装：

```bash
git clone git@github.com:weixin1263831586/Vim-Git-blame.git
install -m 755 Vim-Git-blame/vimb ~/.local/bin/vimb
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

```bash
vimb -w <文件>          # 忽略空白变更
vimb -M -C <文件>       # 检测文件内移动 / 跨文件复制
vimb --blame-args="-w -M -C" <文件>
```

环境变量 `VIMB_SYNC=1` 可强制使用同步 Git 调用（调试用）。

## 快捷键

| 按键 | 位置 | 作用 |
| --- | --- | --- |
| 鼠标单击 / Enter | blame 栏或文件 | 查看该行所属 commit |
| Tab | blame 栏或文件 | 追溯该行到引入它的上一版（入栈，跟随 rename） |
| Backspace | blame 栏或文件 | 返回较新版本（出栈） |
| i | blame 栏或文件 | 轻量 commit 信息 popup |
| y | 任意位置 | 复制当前 commit SHA |
| o | 任意位置 | 在浏览器打开 commit |
| f | commit 视图 | 切换 仅此文件 / 全部文件 |
| gh | blame 栏或文件 | 文件历史（跟随 rename） |
| gl | blame 栏或文件 | 当前行历史（git log -L） |
| q / Backspace / Ctrl-O | commit 视图 | 返回原文件 |
| q / Ctrl-C | blame 栏 | 关闭 blame |
| gb | 任意位置 | 显示或隐藏 blame |
| r / F5 | blame 栏或文件 | 刷新 blame |
| ? | 任意位置 | 显示快捷键提示 |

在源文件窗口按 Tab/Backspace/i/y/o 期间，原有的按键映射会被临时接管，关闭 blame 后完整恢复。

## 工作方式

脚本先校验文件必须位于 Git 工作区内且已被跟踪，然后生成一段临时 Vim script（用后即删），在文件左侧打开一个 `buftype=nofile` 的 blame 缓冲区，底部按需打开 commit 详情缓冲区。blame 数据来自 `git blame --line-porcelain`（完整解析 `previous` / `filename` / `author-mail` 等字段），commit 详情来自 `git show --format=fuller --stat --patch`，历史版本内容来自 `git show <commit>:<path>`，以上 Git 命令均通过 `job_start()` 异步执行（不阻塞编辑），并在解析时建立 hash→行号索引。

追溯历史（Tab）时，源窗口切换为对应历史版本的内容缓冲区（`[vimb-src @<hash>]`），blame 同步切换为对历史版本的 blame；每层的光标位置都会记录，Backspace 返回时精确恢复。

关闭 blame 后，文件的窗口选项（wrap、scrollbind）、缓冲区局部映射和视图位置都会恢复原状。

## 兼容性

- 依赖：`vim`（建议 8.2+，需 `+job` 以启用异步；无此特性自动退回同步）、`git`
- `o` 键需要 `xdg-open`（Linux）或 `open`（macOS）
- 平台：Linux；脚本路径解析使用 `readlink -f` → `realpath` → 纯 bash 归一化三级回退，不依赖 GNU 专有参数

## 开发

```bash
bash test/run.sh          # 回归测试（异步路径）
VIMB_SYNC=1 bash test/run.sh   # 同步路径再跑一遍
```

测试覆盖：普通文件、文件名含空格、中文文件名、空文件、WORKTREE 未提交行、rename 文件（含历史追溯跨旧路径）、CRLF、2 万行大文件、保存自动刷新、关闭 blame 恢复窗口选项与用户映射、fold 状态、commit 面板打开与范围切换、历史栈入栈/出栈/边界行、快捷键与 URL 构造、文件/行历史面板、blame 附加参数。

## 许可

[MIT](LICENSE)
