# TimbreBox 插件开发指南

**语言：简体中文 · [English](./plugin-development.md)**

> 如何为 TimbreBox 编写、打包、安装与调试第三方音源插件。插件是采用 **TimbreBox 插件
> 格式**的单文件 CommonJS 脚本。

---

## 目录

1. [概述](#一概述)
2. [安全模型](#二安全模型)
3. [插件结构](#三插件结构)
4. [支持的函数与数据形状](#四支持的函数与数据形状)
5. [可用的 `require()` 模块](#五可用的-require-模块)
6. [完整示例插件](#六完整示例插件)
7. [安装、更新与管理](#七安装更新与管理)
8. [限制 / 尚未支持](#八限制--尚未支持)
9. [排障](#九排障)

---

## 一、概述

一个 TimbreBox 插件是**单个 JavaScript 文件**，用 CommonJS 约定导出一个音源：

```js
module.exports = {
  platform: 'My Source',
  version: '1.0.0',
  async search(query, page, type) { /* ... */ },
  async getMediaSource(musicItem, quality) { /* ... */ },
};
```

这就是 **TimbreBox 插件格式**——一个插件就是导出 TimbreBox 能理解的函数与元数据字段的
脚本（见下文）。

### 应用如何运行它

每个已安装的插件都会被加载进它自己的**沙箱 JavaScript 引擎**：

| 平台            | 运行时引擎      |
| --------------- | --------------- |
| Windows / Linux | 解释型引擎      |
| macOS           | 系统引擎        |
| Android / iOS   | 无——移动版不会下载或运行插件代码 |

加载时，TimbreBox 按顺序求值：一段小小的**前导（prelude）**（`console`、一个
`axios`/`require` 垫片，以及宿主 HTTP 桥接）、**内置的 shim 库**、一对全新的
`module`/`exports`，最后是你的插件源码。`module.exports` 会被捕获为
`globalThis.__plugin`，导出的函数按需调用。

函数调用在这个单一运行时上是**串行化**的（search 与 resolve 请求绝不交错），
每次调用的入参与返回值都以 JSON 编解码，且每次调用有 **25 秒超时**。引擎运行在应用的
UI 线程上，所以一段不让出执行权的插件代码（比如 `while (true) {}`）会在**三秒后被终止**
（Linux 与 macOS；Windows 上的引擎构建不提供这种终止），下次调用时引擎会重新启动。请用
await 等待网络请求，不要忙等。

引擎在插件第一次被调用时才启动，而不是在应用启动时；**连续五分钟没有调用就会关闭**，下次
调用再启动一个新的。需要跨越这一过程保留的状态请放进你返回的条目里，而不是全局变量。

### HTTP 桥接

你的插件从不直接与网络通信。当你调用 `axios(...)` 时，垫片把请求描述投递给 Dart
宿主（`__hostHttp`），Dart 在**运行时线程之外**按出网策略执行该请求，然后结算
promise（`__resolveHost`）。这是*唯一*一个跨越沙箱边界的能力。

---

## 二、安全模型

插件被视为**不可信代码**。设计上的假设：

- **只暴露 HTTP。** 没有 `fs`、没有 `process`、没有原始套接字、没有任意 `require`、
  没有指向原生的定时器、无法访问其他插件或应用状态。JS 引擎自带的 `fetch` /
  `XMLHttpRequest` 已被移除——`axios` 是唯一的出网途径。
- **出网策略**（在 Dart 层集中实现，作用于*每一个*请求和*每一跳*重定向）：
  - 只允许 `http` / `https` 协议。
  - **内部目标被封禁**：`localhost`、`*.localhost`、`*.local`、`*.internal`，以及所有
    回环、私有、链路本地、运营商级 NAT、多播和保留地址（IPv4、IPv6，以及嵌在 IPv6 里的
    IPv4，例如 `::ffff:127.0.0.1`）。
  - **主机名会先被解析**，解析出的每个地址都必须是公网地址；随后直接连接这个已检查过的地址，
    DNS rebinding 无法中途换成内网地址。
  - 不是标准点分十进制写法的 IPv4（`127.1`、`0177.0.0.1`、`2130706433`、`0x7f000001`）
    一律拒绝。
  - **重定向被手动跟随**（最多 4 跳，超过即报错），每一跳都会重新检查。重定向以 `GET`
    跟随，并丢弃请求体。
  - 响应有上限（插件请求 **8 MB**；安装时脚本上限 **6 MB**），且每个请求有
    **20 秒**的传输超时。
- **隔离：** 每个插件运行在自己的运行时中；某个插件的崩溃或异常不会影响其他插件或应用。
- **安装时的用户同意：** 安装会弹出确认对话框
  （"插件是社区提供的脚本，会以你的名义发起网络请求…请仅安装你信任的来源"），
  用户必须接受（"我信任，安装"）。

> 由于所有流量都经由宿主、以你设备的 IP 发出，**请只安装你信任的音源。** 恶意插件仍能
> 外泄你输入的查询词或抓取跟踪 URL——它只是碰不到你的机器、你的局域网或文件系统。

---

## 三、插件结构

`module.exports` 必须是一个对象。字段分为三组。

### 必填元数据

| 字段       | 类型   | 含义                                                                          |
| ---------- | ------ | ----------------------------------------------------------------------------- |
| `platform` | string | **音源的身份标识。** 在 UI 中显示；决定稳定的音源 id。                          |
| `version`  | string | 语义化版本，如 `"1.2.0"`。显示为 `vX.Y.Z`；缺省时默认为 `0.0.0`。               |

> 音源 id 由 `platform` 派生：
> `plugin_<slug>`，其中 `<slug>` 是 `platform` 转小写并把非字母数字替换为 `_`、截断到
> 32 字符（id 必须匹配 `^[a-z][a-z0-9_]{1,31}$`）。**两个 `platform` 相同的插件会冲突**
> ——安装第二个会替换掉第一个。

### 可选元数据

| 字段     | 类型   | 含义                                                                              |
| -------- | ------ | --------------------------------------------------------------------------------- |
| `srcUrl` | string | 规范的更新 URL。被"检查更新"用来重新拉取并比对。缺省时回退到安装时的 URL。          |
| `author` | string | 在设置中显示于插件名下方。                                                          |

### 函数

你至少必须导出 **`search`**——没有它的插件会在安装时被拒绝
（"插件缺少 search 功能，无法作为音源"）。其余全部可选，用于启用额外能力。
确切的函数签名见下一节。

TimbreBox 为一个插件对外宣告的能力，取决于它导出了哪些函数：

| 导出的函数 | 启用的能力 |
| ----------------- | ------------------ |
| `search`          | 搜索             |
| `getMediaSource`  | 流式 / 播放 |
| `getLyric`        | 歌词             |
| `getTopLists`（+ `getTopListDetail`） | "热门"库中的榜单 |

---

## 四、支持的函数与数据形状

所有函数都可以是 `async`（返回 Promise）。参数与返回值会跨桥接以 JSON 序列化，因此
**只有普通的、JSON 兼容的数据**（不含函数、不含类实例）才能安全往返。

### `MusicItem` 形状

由 `search`、榜单详情等返回。被 `getMediaSource` / `getLyric` 消费（你返回的*整个*对象
会被原样交回，因此你附加的插件私有字段会被保留）。

| 字段        | 类型            | 说明                                                                  |
| ----------- | --------------- | --------------------------------------------------------------------- |
| `id`        | string/number   | **必填。** 没有非空 `id` 的条目会被静默丢弃。                          |
| `title`     | string          | **必填**（trim 后非空）。                                             |
| `artist`    | string          | 可选。为空时回退到音源名称。                                          |
| `album`     | string          | 可选。                                                                |
| `artwork`   | string（URL）   | 封面。TimbreBox 也接受 `coverImg` 或 `pic` 作为回退。                 |
| `duration`  | number          | **秒**（一个裸数字会被当作秒）。                                       |

你可以附加任何 `getMediaSource` 所需的额外字段（曲目 hash、签名令牌、mid 等）——它们会
随该条目一起被携带。用户收藏、加入歌单或留在播放队列里的曲目会连同条目一起保存，重启后
仍可播放——但会**去掉**所有 URL 值和名为 `url` 的字段，以及名字像凭据的字段（`token`、
`cookie`、`auth`、`secret`、`session`、`sign`、`key`、`passw`）。请让 `getMediaSource` 能
凭稳定的 id 重新解析；凭据类字段只在应用退出前有效。

### `search(query, page, type) -> { isEnd, data }`

```js
async function search(query, page, type) {
  // type 在 TimbreBox 中始终是 'music'（不使用其他搜索类型）。
  // page 从 1 开始。
  return {
    isEnd: false,               // 没有更多分页时为 true
    data: [ /* MusicItem[] */ ] // 每个条目都必须有 id
  };
}
```

- 若 `isEnd` 为假值，TimbreBox 会以 `page + 1` 作为下一个游标。
- 返回值不是对象、或其 `data` 不是数组时，会得到一个空的结果页（而非错误）。

### `getMediaSource(musicItem, quality) -> { url, headers?, userAgent? }`

```js
async function getMediaSource(musicItem, quality) {
  return {
    url: 'https://cdn.example.com/audio/123.mp3',
    headers: { Referer: 'https://example.com/' }, // 可选
    userAgent: 'Mozilla/5.0 ...'                  // 可选
  };
}
```

- **音质回退：** TimbreBox 会反复调用它，按 **`standard` → `high` → `super` → `low`**
  的顺序尝试各音质，并在第一个带非空 `url` 的结果处停止。因此一个只暴露
  `high`/`super` 的插件依然可用。（注意：TimbreBox **不会**传入用户偏好的音质——它只是
  按这个固定顺序探测。见[限制](#八限制--尚未支持)。）
- **所有 URL 都经由回环代理播放。** 代理会在每一跳注入你返回的 `headers` 和/或
  `userAgent`（媒体播放器自身无法附加任意请求头），并用出网策略检查每一个重定向跳转。
  `userAgent` 会作为 `User-Agent` 并入 headers。
- MIME 类型由 URL 后缀推断（`.m4a`/`.mp4`、`.mp3`、`.flac`、`.ogg`）；尽量带上可识别
  的后缀。
- **`url` 必须是公网的 `http(s)` 地址。** 在播放、代理或下载之前，它会经过同样的出网策略；
  `file://` 和本机/局域网地址会被拒绝。

### `getTopLists() -> [ { title, data } ]`

```js
async function getTopLists() {
  return [
    {
      title: 'Featured Charts',      // 分组标题（不会单独展示）
      data: [
        { id: 'chart_hot', title: 'Hot 100', coverImg: 'https://…/cover.jpg' },
        // ...
      ]
    }
  ];
}
```

- TimbreBox 会把**所有分组扁平化**为一个榜单列表。
- 每个榜单条目需要 `id` + 非空 `title`。封面取自 `coverImg` / `artwork` / `pic`
  （取第一个存在的）。

### `getTopListDetail(topListItem, page) -> { isEnd, musicList | data }`

```js
async function getTopListDetail(topListItem, page) {
  // topListItem 就是你从 getTopLists 返回的那个榜单对象原样。
  return {
    isEnd: true,
    musicList: [ /* MusicItem[] */ ] // 也接受 'data'
  };
}
```

TimbreBox 目前只请求第 `1` 页，并读取 `musicList`（或 `data`）。

### `getLyric(musicItem) -> { rawLrc | lrc }`

```js
async function getLyric(musicItem) {
  return { rawLrc: '[00:00.00] line one\n[00:03.20] line two' };
  // 'lrc' 与 'lyric' 也可作为文本字段。
}
```

返回 LRC 格式的歌词文本。空值/缺省表示"无歌词"。

---

## 五、可用的 `require()` 模块

只有这个**白名单**能被解析；任何其他 `require('…')` 都会抛出
`插件请求了不允许的模块：<name>`。以下是通过 `require()` 可用的模块：

| 模块          | 是什么                                                                     |
| ------------- | ------------------------------------------------------------------------- |
| `axios`       | 一个 **HTTP 客户端**——接到宿主 HTTP 桥接的 fetch 垫片。见下文。            |
| `crypto-js`   | 加密辅助：哈希 / HMAC / AES 等（`CryptoJS.MD5`、`CryptoJS.HmacSHA256`、…）。 |
| `cheerio`     | 一个带类 jQuery API 的 HTML 解析器（`cheerio.load(html)`）。               |
| `he`          | HTML 实体编解码。                                                          |
| `dayjs`       | 日期解析/格式化。                                                          |
| `qs`          | 查询串 stringify/parse。                                                   |
| `big-integer` | 任意精度整数（用于签名方案）。                                             |

你可以 `require('axios')` 或直接使用全局的 `axios`——两者是同一个垫片。

### `axios` 垫片：配置与响应

支持的请求形式：

```js
axios(config)                       // config: { url, method?, headers?, params?, data?, responseType? }
axios(urlString)                    // { url: urlString } 的简写
axios.get(url, config?)             // method 设为 'GET'
axios.post(url, data, config?)      // method 设为 'POST'，body = data
```

- `params`（对象）会被并入 URL 查询串。
- `data` 作为非 GET/HEAD 请求的请求体发送；字符串按原样发送，对象会被 JSON 序列化。
- **响应形状**为 `{ status, headers, data }`：
  - `status` — HTTP 状态码（数字）。
  - `headers` — 响应头（对象；多值以 `, ` 连接）。
  - `data` — 响应体。默认情况下垫片会对字符串响应体**自动 JSON 解析**；设置
    `responseType: 'text'`（或 `'arraybuffer'` / `'blob'`）可将其保留为原始**文本**
    （桥接始终以 UTF-8 文本交付响应体——没有真正的二进制通道，因此把
    `arraybuffer`/`blob` 理解为"给我原始字符串"）。

```js
const res = await axios.get('https://api.example.com/search', {
  params: { q: 'hello', page: 1 },
  headers: { 'User-Agent': 'TimbreBox' },
});
// res.status === 200
// res.data 已是被解析的对象（自动 JSON），若非 JSON 则为字符串。
```

### 哪些是不可用的

- 没有 `fs`、`path`、`os`、`child_process`、`net`、`http`/`https`（Node 的）、`crypto`
  （Node 的——请用 `crypto-js`）、`buffer`，或任何其他 Node 内置模块。
- 没有 `process`、没有环境变量、没有指向原生代码的定时器。
- **没有 cookie jar 持久化。** 每次 `axios` 调用彼此独立；`Set-Cookie` 不会被存储或
  重放。如果某个音源需要会话 Cookie，你必须自己从响应头读出它，并在下一个请求的
  `headers` 中显式传回。
- 没有 `import`/ESM——请使用 CommonJS（`module.exports`、`require`）。

---

## 六、完整示例插件

一个精简但真实的、**基于 API** 的插件，使用 `axios` + `crypto-js`。它实现了
`platform`、`version`、`search` 与 `getMediaSource`，并演示了如何把一个插件私有字段
（`songmid`）从搜索携带到媒体解析，以及如何返回带请求头校验的播放 URL。

```js
// my-source.js — 一个 TimbreBox 插件。
const axios = require('axios');
const CryptoJS = require('crypto-js');

const API = 'https://api.example.com';

// 有些 API 需要一个签名时间戳。crypto-js 在沙箱内运行。
function sign(path, ts) {
  return CryptoJS.MD5(`${path}:${ts}:my-secret-salt`).toString();
}

async function search(query, page, type) {
  // type 在 TimbreBox 中始终是 'music'——无需分支判断。
  const ts = Date.now();
  const res = await axios.get(`${API}/search`, {
    params: { keyword: query, page, sign: sign('/search', ts), ts },
    headers: { 'User-Agent': 'TimbreBox/1.0' },
  });

  // res.data 已自动 JSON 解析。处处防御——永不信任 API。
  const list = (res.data && res.data.songs) || [];
  const data = list.map((s) => ({
    id: String(s.id),              // 必填，必须是稳定的非空 id
    title: s.name,                 // 必填
    artist: (s.artists || []).map((a) => a.name).join(', '),
    album: s.album && s.album.name,
    artwork: s.album && s.album.cover,   // 也接受 'coverImg' / 'pic'
    duration: Math.round((s.durationMs || 0) / 1000), // 秒
    songmid: s.mid,                // 插件私有：携带进 getMediaSource
  }));

  return {
    isEnd: data.length === 0 || page >= (res.data.totalPages || 1),
    data,
  };
}

async function getMediaSource(musicItem, quality) {
  // quality 取值之一：'standard' | 'high' | 'super' | 'low'
  // TimbreBox 按该顺序探测，取第一个带 url 的结果。
  const ts = Date.now();
  const res = await axios.get(`${API}/url`, {
    params: {
      mid: musicItem.songmid,      // 我们在 search() 里附加的私有字段
      br: quality,
      sign: sign('/url', ts),
      ts,
    },
  });

  const url = res.data && res.data.playUrl;
  if (!url) return null;           // 此音质无 url → TimbreBox 尝试下一个

  return {
    url,
    // 如果 CDN 需要 Referer/Cookie/UA，在此返回，TimbreBox 会
    // 自动代理播放并按每一跳注入这些请求头。
    headers: { Referer: 'https://example.com/' },
    userAgent: 'Mozilla/5.0 (compatible; TimbreBox)',
  };
}

module.exports = {
  platform: 'Example Source',      // 身份标识 + 决定音源 id
  version: '1.0.0',                // 语义化版本
  author: 'you',                   // 可选
  srcUrl:                          // 可选，被"检查更新"使用
    'https://example.com/plugins/my-source.js',
  search,
  getMediaSource,
};
```

一个**HTML 抓取**的变体则会改用 `require('cheerio')`，并用 `cheerio.load(html)` 解析
`res.data`（以文本形式返回）。

---

## 七、安装、更新与管理

### 在哪里安装

**设置 (Settings) → 音源插件 (Music Source Plugins)。**

把下列之一粘贴进 URL 输入框
（"粘贴插件 .js 原始链接，或订阅 JSON 地址"）并点按 **安装 (Install)**：

1. **一个原始插件 `.js` URL**——直接指向脚本文件的链接，例如
   `https://example.com/plugins/plugin.js`。插件脚本、订阅和检查更新都**只通过 https**
   从公网主机获取，每一跳重定向都会检查。
   > 如果你的托管方为某个文件提供了"预览"页面 URL，TimbreBox 会尝试把它解析为对应的
   > 原始文件 URL，因此两种形式通常都可用。
2. **一个订阅 JSON URL**——一份列出许多插件的文档：

   ```json
   {
     "desc": "My plugin bundle",
     "plugins": [
       { "name": "Source A", "url": "https://…/a.js", "version": "1.0.0" },
       { "name": "Source B", "url": "https://…/b.js", "version": "2.1.0" }
     ]
   }
   ```

   `plugins[]` 中的每个 `url` 都会被拉取并安装；只要至少有一个成功，个别失败会被容忍。

安装会把脚本运行一次，以读取 `platform`（必填）并确认存在 `search` 函数，然后将其持久化。
你必须先接受**信任确认对话框**。

### 更新如何工作

点按 **检查更新 (Check for updates)**。对每个带 `srcUrl` 的已安装插件，TimbreBox 会重新
拉取脚本，并将其 **SHA-256** 与已存储的哈希比对。若内容有变，则重新安装（并重新读取
元数据）；若哈希一致，则原样保留（"插件已是最新"）。没有 `srcUrl` 的插件永远不会被
自动更新。

### 启用 / 禁用 / 卸载

- 每个插件旁的**开关**将其作为搜索音源启用/禁用（状态持久化在其 `manifest.json` 中）。
- **垃圾桶图标（卸载）** 用于卸载：注销该音源并删除其存储的文件。

### 插件存储在哪里

在 App 支持目录下：

```
<appSupport>/plugins/<id>/
    plugin.js        # 原始脚本
    manifest.json    # { id, platform, version, author, srcUrl, sha256, enabled }
```

`<id>` 是派生出的 `plugin_<slug>` id。应用启动时，每个已存储的插件都会被重新加载进一个
全新的运行时；加载失败的插件会被跳过，而不是让应用崩溃。

---

## 八、限制 / 尚未支持

TimbreBox 实现了插件接口的一个**子集**。以下这些**目前尚未接线**——导出它们不会有任何
效果：

- **登录 / 鉴权流程：** 基于 Cookie 的登录、`userVariables` 以及持久化 cookie jar 均不
  支持。`Set-Cookie` 不会在请求之间被存储。
- **元数据函数：** `getMusicInfo`、`getAlbumInfo`、`getArtistWorks`、
  `getMusicSheetInfo`、`getRecommendSheetsByTag`，以及任何 `import*`
  （`importMusicItem`、`importMusicSheet`）都**不会被调用**。
- **非音乐搜索：** 传给 `search` 的 `type` 参数**始终是 `'music'`**。不会请求
  专辑/歌手/歌单/歌词等搜索类型。
- **音质偏好透传：** `getMediaSource` 按固定顺序探测（`standard → high → super → low`）；
  用户所选的音质**不会**被透传——只使用这个回退顺序。
- **榜单详情分页：** `getTopListDetail` 目前只对第 `1` 页调用。
- **地域后端：** 许多社区音源指向**地域受限**的后端，从你的网络可能被**地域封锁或限流**。
  一个插件可能安装得很顺利，却仅仅因为其 API 从你的位置无法访问而返回不了可播放的 URL。

请让你的插件保持精简：只要存在 `platform`、`version` 与 `search`，插件就能工作；不支持
的钩子会被直接忽略。

---

## 九、排障

| 症状 / 提示信息 | 可能原因与修复 |
| ----------------- | ------------------ |
| **"插件缺少 search 功能，无法作为音源"** | `module.exports` 没有 `search` 函数。每个音源插件都必须导出 `search`。检查你是否赋值了 `module.exports`（而不是只写 `exports.x = …` 而被覆盖），以及 `search` 是否为函数。 |
| **"这不是有效的插件（缺少 platform 字段）"** | `platform` 必须是非空的**字符串**。 |
| **"插件脚本无法加载：…"** | 脚本在顶层抛出了异常（语法错误、调用了缺失的全局变量，或 `require('somenode')`）。只有白名单模块能被解析。 |
| **"插件请求了不允许的模块：X"** | 你 `require` 了白名单（`axios`、`crypto-js`、`cheerio`、`he`、`dayjs`、`qs`、`big-integer`）之外的东西。Node 内置模块（`fs`、`crypto`、`http`、`buffer`）不可用。 |
| **运行时的 `cheerio` 类 / `require` 错误** | 确保你 `require('cheerio')`（已内置），并把 `res.data` **以文本形式**喂给它——设置 `responseType: 'text'`，使响应体不被 JSON 解析成对象。 |
| **"插件未返回可播放的地址"** | `getMediaSource` 在四个被探测的音质上都没有返回对象、或没有非空 `url`。请确认媒体 API 可达（见地域封锁），并确保你返回 `{ url }`。在某个音质返回 `null` 可让 TimbreBox 尝试下一个。 |
| **"出于安全，禁止访问本机或内网地址：…" / "出于安全，不允许使用该协议：…"**（英文界面："Blocked for safety: …"） | 出网策略拦截了该请求或返回的播放 `url`：内部/局域网/回环主机（包括公网域名解析到的内网地址）、非 http(s) 协议，或**重定向到内部地址**。请把插件指向一个公网 https 端点。 |
| **"曲目信息已过期，请重新搜索"** | 对一个 TimbreBox 内存中已不再持有的条目尝试了播放（例如重新加载之后）。重新搜索一次，让完整的 `MusicItem` 被重新缓存。 |
| **请求 "timed out" / 卡住** | 请求有 20 秒的传输上限，每次函数调用有 25 秒上限；超过 8 MB 的响应会被拒绝。避免在插件内下载过大的响应体。 |
| **搜索什么都没返回但也没报错** | `search` 返回了非对象、`data` 不是数组，或每个条目都缺少 `id`/`title`。每个条目都需要非空的 `id` **和** `title`。 |
| **重启后插件悄悄消失** | 已存储的脚本重新加载失败（例如它现在在加载时抛错）。请从一个已知可用的 URL 重新安装。 |
| **两个插件互相覆盖** | 它们共用了相同的 `platform`（→ 派生出相同的 id）。给每个插件一个不同的 `platform`。 |

### 调试技巧

- 插件中的 `console.log` / `console.warn` / `console.error` 会被转发到应用的调试日志
  （以 `[plugin]` 为前缀）。运行 debug 构建并观察日志，以追踪请求与解析。
- 先用确切的 `axios` 配置测试你的 API 调用——记住除非你传 `responseType: 'text'`，
  否则响应体会被自动 JSON 解析。
- 当某个音源需要请求头来播放时，确认它们是从 `getMediaSource` 返回的（而不仅是在搜索
  时使用）——播放代理只对 `getMediaSource` 的请求头生效。
