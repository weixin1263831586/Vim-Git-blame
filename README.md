# vimb

一个小巧、可预期的 Vim Git 代码历史追溯（Code Archaeology）工作区。一条命令 `vimb <文件>` 启动：左侧逐行 blame、双向光标同步、单击查看 commit patch，还能用 Tab 逐层向前追溯一行的历史来源，直到最初引入它的提交。

发布物仍是单个 Bash 脚本，除 `vim` 和 `git` 外无任何运行时依赖；开发源码按职责拆分在 `src/`，由构建脚本生成 `vimb`。

## 功能

- 左侧 blame 栏逐行显示 commit 短哈希、作者、日期和行号，未提交的工作区改动标记为 `WORKTREE`
- blame 栏与文件窗口双向同步光标位置，`scrollbind` 联动滚动
- 当前行的 commit 自动高亮，同属一个 commit 的所有行一起标出
- 鼠标单击或 Enter 查看该行所属 commit 的完整信息（fuller 格式 + stat + patch）
- 双击/三击/拖拽完全沿用 Vim 原生选区行为；在任意面板释放左键即自动把完整选区复制到剪贴板（双击选词、三击选行），并保持选区高亮；优先使用 Vim/system clipboard、`wl-copy`/`xclip`/`xsel` 等本地接口（X11 下同时更新主选择区，支持中键粘贴），远程终端回退到 OSC 52
- **Tab 向前追溯**：基于 `previous` 字段入栈显示历史版本文件，rename/移动过的代码自动跟随旧路径；Backspace 逐层返回，blame 栏显示当前深度（如 `vimb blame 2 层 @79583ef`）
- blame 视觉增强：连续相同 commit 的行合并显示（块首行显示作者/日期）、相邻 commit 块循环底色区分（256 色终端）、按当前时间计算的代码年龄热力（hash 列按新旧绿→蓝→灰着色）
- 源窗口状态栏常驻显示当前行 commit 摘要（current-line compact 模式），关闭 blame 后恢复
- `gh` 文件历史（`git log --follow`，rename 后继续追溯）；`gl` 当前行历史（`git log -L`）；历史记录支持 Enter 查看 commit、y 复制 SHA、o 浏览器打开、Tab 直接进入所选 revision
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

安装器默认安装 `main` 的最新提交：先通过 GitHub API 把 `main` 解析成不可变 commit SHA，再从该 SHA 下载并校验脚本结构，之后运行 `vimb --update` 即可保持最新。需要精确固定安装内容时（审计、复现），显式指定来源与校验和：

```bash
VIMB_REF=<commit> VIMB_SHA256=<该 commit 中 vimb 的 SHA-256> sh install.sh
```

或手动安装：

```bash
git clone git@github.com:weixin1263831586/Vim-Git-blame.git
install -m 755 Vim-Git-blame/vimb ~/.local/bin/vimb
```

要求 `~/.local/bin` 在 `PATH` 中。已安装的用户可以随时自更新到最新版：

```bash
vimb --update     # 或简写 vimb -u
```

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
vimb --update    # 从 GitHub 更新自身到最新版（简写 vimb -u）
```

```bash
vimb -w <文件>          # 忽略空白变更
vimb -M -C <文件>       # 检测文件内移动 / 跨文件复制
```

`--blame-args` 支持追加额外的 blame 参数；建议只使用不改变输出行范围的选项（如 `-w`/`-M`/`-C`/`--ignore-rev`），会改变行范围的选项（如 `-L`）会破坏 blame 与源窗口的行对齐。

Gerrit 用户：SSH 远端 `ssh://user@gerrit.host:29418/project` 可自动识别；Web 地址与 SSH 不同时，配置 `git config vimb.webBaseUrl https://gerrit.example.com` 或环境变量 `VIMB_WEB_BASE_URL`。

环境变量 `VIMB_SYNC=1` 可强制使用同步 Git 调用（调试用）。历史源码缓冲区默认最多缓存 20 层，文件/行历史默认最多读取 500 条；可分别通过 `VIMB_HISTORY_CACHE_DEPTH` 和 `VIMB_HISTORY_LIMIT` 调整。

## 快捷键

| 按键 | 位置 | 作用 |
| --- | --- | --- |
| 鼠标单击 / Enter | blame 栏或文件 | 查看该行所属 commit |
| 鼠标双击 | 源码 / blame / commit / history | 原生选词 + 释放自动复制到剪贴板 |
| 鼠标拖拽 | 源码 / blame / commit / history | 原生选区 + 释放自动复制完整文本 |
| Tab | blame 栏或文件 | 追溯该行到引入它的上一版（入栈，跟随 rename） |
| Tab | history commit 行 | 进入所选 revision（跟随当时路径） |
| Backspace | blame 栏或文件 | 返回较新版本（出栈） |
| i | blame 栏或文件 | 轻量 commit 信息 popup |
| y | blame / 文件 / commit / history commit 行 | 复制当前 commit SHA |
| o | blame / 文件 / commit / history commit 行 | 在浏览器打开 commit |
| f | commit 视图 | 切换 仅此文件 / 全部文件 |
| gh | blame 栏或文件 | 文件历史（跟随 rename） |
| gl | blame 栏或文件 | 当前行历史（git log -L） |
| Enter | history commit 行 | 打开所选 commit |
| q / Backspace / Ctrl-O | commit 视图 | 返回原文件 |
| q / Ctrl-C | blame 栏 | 关闭 blame |
| gb | 任意位置 | 显示或隐藏 blame |
| r / F5 | blame 栏或文件 | 刷新 blame |
| ? | 任意位置 | 显示快捷键提示 |

在源文件窗口按 Tab/Backspace/i/y/o 期间，原有的按键映射会被临时接管，关闭 blame 后完整恢复。

## 工作方式

脚本先校验文件必须位于 Git 工作区内且已被跟踪，然后生成一段临时 Vim script（用后即删），在文件左侧打开一个 `buftype=nofile` 的 blame 缓冲区，底部按需打开 commit 详情缓冲区。blame 数据来自 `git blame --line-porcelain`（完整解析 `previous` / `filename` / `author-mail` 等字段），commit 详情来自 `git show --format=fuller --stat --patch`，历史版本内容来自 `git show <commit>:<path>`，以上 Git 命令均通过 `job_start()` 异步执行（不阻塞编辑），并在解析时建立 hash→行号索引。

追溯历史（Tab）时，源窗口切换为对应历史版本的内容缓冲区（`[vimb-src @<hash>]`），blame 同步切换为对历史版本的 blame；每层的光标位置都会记录，Backspace 返回时精确恢复。

History Explorer 的 Tab 会用 Git line-log 找到当前逻辑行的稳定身份，再在目标 revision 的 blame 中反查位置，因此目标行前方发生插入/删除时不会简单照搬数字行号。

关闭 blame 后，文件的窗口选项（wrap、scrollbind）、缓冲区局部映射和视图位置都会恢复原状。

## 兼容性

- 依赖：`vim`（8.2.1119+；需 `+job` 以启用异步，无此特性自动退回同步）、`git`
- `o` 键需要 `xdg-open`（Linux）或 `open`（macOS）
- 平台：Linux；脚本路径解析使用 `readlink -f` → `realpath` → 纯 bash 归一化三级回退，不依赖 GNU 专有参数

## 开发

```bash
bash scripts/build.sh      # 从 src/ 重新生成单文件发布物 vimb
bash test/run.sh          # 回归测试（异步路径）
VIMB_SYNC=1 bash test/run.sh   # 同步路径再跑一遍
bash scripts/verify-release-payload.sh  # 下载并验证安装器默认路径（main 最新提交）
```

`src/vim/` 使用职责明确的语义化文件名；模块加载顺序只由 `scripts/build.sh` 的 `MODULES` 清单决定，不依赖目录遍历或文件名排序。构建脚本会拒绝缺失、重复以及未登记的 `.vim` 模块，避免新增文件被静默遗漏。所有模块最终拼进同一个 Vim script，共享 script-local (`s:`) 命名空间；当前依赖顺序为 `state → git → commit_cache → visual → ui → blame → stack → history → commit_panel → lifecycle → remote → bootstrap`。新增跨模块调用时，应确保提供者排在使用者之前，并同步更新 `MODULES` 清单。

测试覆盖：普通文件、文件名含空格、中文文件名/作者显示宽度、空文件、WORKTREE 未提交行、rename 文件（含历史追溯跨旧路径、UTF-8 文件名 rename 后追溯）、CRLF、2 万行大文件、保存自动刷新、关闭 blame 恢复窗口选项/带引号状态栏/用户映射、syntax off 保持、fold 状态、commit 面板打开与范围切换、历史栈入栈/出栈/边界行/**blame revision 坐标映射**/**多 hunk 映射**/**新增行拦截**/**Tab 关闭与双击竞态**、快捷键与 URL 构造（含 Gerrit SSH 远端）、交互式文件/行历史（含 rename 旧路径 revision）、历史层行历史、异步关闭竞态、blame 附加参数、256 色大文件视觉路径、CLI `--` 解析；另有 pty + SGR 真实鼠标序列的端到端测试（首次/连续双击复制、拖拽复制、blame 双击不误开面板、双击后拖拽扩展选区、commit 面板复制），无需真实 X 显示。

CI 会验证 Vim 8.2.1119、Vim 9.0 与最新稳定版，并组合覆盖异步/同步 Git 路径及低色彩/256 色终端；构建后还会确认 `vimb` 与 `src/` 完全一致。

## 许可

[MIT](LICENSE)
