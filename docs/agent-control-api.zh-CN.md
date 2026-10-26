# TimbreBox Agent 控制 API

**语言：简体中文 · [English](./agent-control-api.md)**

---

一个本机 HTTP 接口，让本地 agent、CLI 或脚本控制 TimbreBox 播放器。**默认开启**，
可在 **设置 → 常规 → Agent 控制** 关闭；设置面板会显示地址。

## 后台运行

只要 app 的**进程**存活，它就持续提供本 API —— **无需**保持前台窗口。关闭窗口后 app（及控制
服务器）会在各桌面端继续后台运行：

- **macOS** —— 窗口隐藏；从程序坞点击或再次启动即可恢复；退出用 Cmd+Q。
- **Windows / Linux** —— 窗口隐藏；**重新启动**即可把窗口带回（单实例）；退出用 `POST /quit`
  （`timbrebox-ctl quit`）。

想启动时不抢占前台，可用后台方式启动 —— macOS：`open -g -a TimbreBox`。`POST /quit` 在任意
平台都能干净地退出整个 app（窗口已隐藏、又没有 Cmd+Q 时很有用）：退出前会保存会话并写完
待写入的文件。

## 安全

- 仅绑定 **本机回环**（`127.0.0.1`），机器之外无法访问。
- **拒绝网页发来的请求。** 浏览器里的网页同样可以向 `127.0.0.1` 发请求，所以服务端还会：
  - 只接受 `Host` 为 `127.0.0.1:<端口>` 或 `localhost:<端口>` 的请求（防 DNS rebinding）；
  - 拒绝带 `Origin` 头、或 `Sec-Fetch-Site` 不是 `none` 的请求（浏览器会给网页发出的请求加上这些头）；
  - 动作只接受 `POST`，普通链接或 `<img>` 无法触发（否则返回 `405`；读取用 `GET`）。
- **每次运行一个令牌。** API 每次启动时，app 会生成一个新的 256 位随机令牌，写入支持目录下
  名为 `control-token` 的文件，只有你的账户能读取（macOS 与 Linux 上权限为 `0600`；Windows
  上位于本用户私有的 AppData 目录）。每个请求都必须在 `X-TimbreBox-Token` 头里带上它，否则返回
  `401`。本机其他用户、以及读不到你文件的程序都无法控制播放器。API 停止时该文件会被删除：

  | 平台 | 令牌文件 |
  |---|---|
  | macOS | `~/Library/Containers/io.timbrebox.timbreboxApp/Data/Library/Application Support/io.timbrebox.timbreboxApp/control-token` |
  | Linux | `${XDG_DATA_HOME:-~/.local/share}/io.timbrebox.timbrebox_app/control-token` |
  | Windows | `%APPDATA%\io.timbrebox\TimbreBox\control-token` |

  设置 → 常规 → Agent 控制 会显示这个路径。`tools/timbrebox-ctl`、Dart CLI 与 MCP 服务会自动
  读取；可用 `TIMBREBOX_TOKEN_FILE`（路径）或 `TIMBREBOX_TOKEN`（令牌本身）覆盖。
- macOS 需要 `com.apple.security.network.server` 权限（已内置）。

## 发现与 CLI

服务优先绑定固定端口段 **8787–8796**（取第一个空闲的），本地 agent 无需知道随机端口
即可发现。令牌通过标准输入交给 curl（`-H @-`），不要写在命令行里，否则其他用户能在进程列表
中看到：

```bash
TOKEN_FILE=...   # 你所在平台的令牌文件，见上表
tb() { printf 'X-TimbreBox-Token: %s\n' "$(cat "$TOKEN_FILE")" | curl -H @- "$@"; }
for p in 8787 8788 8789 8790 8791 8792 8793 8794 8795 8796; do
  tb -s "http://127.0.0.1:$p/" | grep -q 'TimbreBox control API' && BASE="http://127.0.0.1:$p" && break
done
```

仓库提供封装脚本 **`tools/timbrebox-ctl`**，自动发现并封装所有端点（如
`tools/timbrebox-ctl search "周杰伦"`、`tools/timbrebox-ctl play-ref <source> <item>`）。
AI agent 可用 `.claude/skills/timbrebox-control/` 技能。

（app 也会把地址和令牌文件的路径——不是令牌本身——写到 `~/.timbrebox/control.json`，但
macOS 沙箱下 app 的 HOME 在容器内，所以上面的端口扫描才是可靠的跨平台发现方式。）

## 端点

所有响应为 JSON。读取用 `GET`，其余一律用 `POST`；用错方法时服务端返回 `405`。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/` | 发现文档（端点 + 当前状态） |
| GET | `/status` | 播放状态：`playing`、`positionMs`、`volume`、`loop`、`queueLength`、`track` |
| GET | `/queue` | 播放队列（`items[]`） |
| GET | `/sources` | 音源列表（`id`、`name`、`enabled`） |
| GET | `/lyric` | 当前曲目歌词（仅插件音源），否则 `null` |
| POST | `/search?q=` | 搜索所有启用音源，返回 `results[]`（`source`、`item`、`title`、`artist`） |
| POST | `/play` `/pause` `/toggle` `/next` `/previous` `/stop` | 播放控制 |
| POST | `/seek?ms=<毫秒>` | 跳转到指定位置（毫秒） |
| POST | `/volume?level=<0..1>` | 设置音量 |
| POST | `/mode?loop=<queue\|track\|off\|shuffle>` | 设置循环模式 |
| POST | `/play-ref?source=<id>&item=<id>` | 播放此前 `/search` 得到的曲目 |
| POST | `/play-queue?i=<索引>` | 播放队列指定索引的曲目 |
| POST | `/source?id=<id>&enabled=<true\|false>` | 启用/停用某音源 |
| POST | `/quit` | 退出整个 app（后台实例） |

出错返回相应 HTTP 状态码与 `{ "error": "..." }`；缺少令牌或令牌已过期返回 `401`。

## 示例

```bash
BASE="http://127.0.0.1:<端口>"   # 地址见 设置 → 常规 → Agent 控制
# tb = 带令牌头的 curl，定义见「发现与 CLI」

# 当前状态
tb "$BASE/status"

# 搜索后播放第一条结果
tb -X POST "$BASE/search?q=jazz"
tb -X POST "$BASE/play-ref?source=audius&item=abc123"

# 控制 + 音量 + 循环
tb -X POST "$BASE/toggle"
tb -X POST "$BASE/volume?level=0.6"
tb -X POST "$BASE/mode?loop=shuffle"

# 播放队列中的某项
tb -X POST "$BASE/play-queue?i=2"
```
