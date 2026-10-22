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
平台都能干净地退出整个 app（窗口已隐藏、又没有 Cmd+Q 时很有用）。

## 安全

- 仅绑定 **本机回环**（`127.0.0.1`）随机端口。回环即安全边界：机器之外无法访问，
  只有本地进程能连接。
- **无令牌 / 无认证** —— 既然只有本地进程能连，令牌只会增加麻烦而不增加保护。
- macOS 需要 `com.apple.security.network.server` 权限（已内置）。

## 发现与 CLI

服务优先绑定固定端口段 **8787–8796**（取第一个空闲的），本地 agent 无需知道随机端口
即可发现：

```bash
for p in 8787 8788 8789 8790 8791 8792 8793 8794 8795 8796; do
  curl -s "http://127.0.0.1:$p/" | grep -q 'TimbreBox control API' && BASE="http://127.0.0.1:$p" && break
done
```

仓库提供封装脚本 **`tools/timbrebox-ctl`**，自动发现并封装所有端点（如
`tools/timbrebox-ctl search "周杰伦"`、`tools/timbrebox-ctl play-ref <source> <item>`）。
AI agent 可用 `.claude/skills/timbrebox-control/` 技能。

（app 也会把地址写到 `~/.timbrebox/control.json`，但 macOS 沙箱下 app 的 HOME 在容器内，
所以上面的端口扫描才是可靠的跨平台发现方式。）

## 端点

所有响应为 JSON。读操作用 `GET`，动作用 `POST`（服务端不强制方法，此为约定）。

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/` | 发现文档（端点 + 当前状态） |
| GET | `/status` | 播放状态：`playing`、`positionMs`、`volume`、`loop`、`queueLength`、`track` |
| GET | `/queue` | 播放队列（`items[]`） |
| GET | `/sources` | 音源列表（`id`、`name`、`enabled`） |
| GET | `/lyric` | 当前曲目歌词（仅插件音源），否则 `null` |
| GET | `/search?q=` | 搜索所有启用音源，返回 `results[]`（`source`、`item`、`title`、`artist`） |
| POST | `/play` `/pause` `/toggle` `/next` `/previous` `/stop` | 播放控制 |
| POST | `/seek?ms=<毫秒>` | 跳转到指定位置（毫秒） |
| POST | `/volume?level=<0..1>` | 设置音量 |
| POST | `/mode?loop=<queue\|track\|off\|shuffle>` | 设置循环模式 |
| POST | `/play-ref?source=<id>&item=<id>` | 播放此前 `/search` 得到的曲目 |
| POST | `/play-queue?i=<索引>` | 播放队列指定索引的曲目 |
| POST | `/source?id=<id>&enabled=<true\|false>` | 启用/停用某音源 |
| POST | `/quit` | 退出整个 app（后台实例） |

出错返回相应 HTTP 状态码与 `{ "error": "..." }`。

## 示例

```bash
BASE="http://127.0.0.1:<端口>"   # 地址见 设置 → 常规 → Agent 控制

# 当前状态
curl "$BASE/status"

# 搜索后播放第一条结果
curl "$BASE/search?q=jazz"
curl "$BASE/play-ref?source=audius&item=abc123"

# 控制 + 音量 + 循环
curl "$BASE/toggle"
curl "$BASE/volume?level=0.6"
curl "$BASE/mode?loop=shuffle"

# 播放队列中的某项
curl "$BASE/play-queue?i=2"
```
