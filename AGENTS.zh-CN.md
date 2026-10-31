# TimbreBox · Agent 开发协作规则

**语言：简体中文 · [English](./AGENTS.md)**

## 项目目标

TimbreBox 是面向 Windows、macOS、Linux、iOS、Android 的轻量播放器与通用音源插件宿主。
当前内置 Audius、Openverse、Internet Archive、Radio Browser。YouTube、B 站、抖音、TikTok
明确纳入插件目标，由 `homeplay-plugins` 维护和分发，不再强制内置。不按平台名称、是否存在公开
API、用户配置需求或旧版本排期预先排除来源；具体实现的访问条件、权利依据和分发要求分别核实。
任何能力都不得提前作为已实现能力。

详细规范与设计（范围真源、实现边界、阶段计划、来源准入等）在**本地内部文档**
`docs/prd/` 与 `docs/internal/` 中，仅本地保留、不随仓库发布；开始任务前先读。

## gstack / Agent 技能路由

gstack 已为 Codex 安装。根据任务选择最小必要工作流：

| 任务 | 必用技能 / 检查 |
|---|---|
| 新产品范围、版本取舍 | `gstack-office-hours` → `gstack-plan-ceo-review` |
| 架构、协议、数据流、测试计划 | `gstack-plan-eng-review` |
| UI 结构、视觉系统、交互方案 | `gstack-plan-design-review` 或 `gstack-design-consultation` |
| 实现后代码检查 | `gstack-review` |
| 真机/浏览器/端到端验证 | `gstack-qa`；仅报告时 `gstack-qa-only` |
| 安全、凭据、外部二进制、IPC | `gstack-cso` 与 `gstack-guard` |
| 发布前文档和交付 | `gstack-document-release` → `gstack-ship` |

对常规小修复不强制运行完整工作流；不得为了“使用技能”而引入无关浏览器、遥测、
远程服务或常驻进程。所有外部工具仍须符合内部规范的低资源、凭据保护与本地优先约束；来源适配器产生的匿名临时会话状态只能驻留内存。

### TimbreBox 控制 skill（驱动运行中的播放器）

仓库自带一个项目 skill `timbrebox-control`（`.claude/skills/`）以及 `tools/timbrebox-ctl`
封装脚本，用于通过本地回环控制 API 驱动**正在运行**的应用（默认开启；拒绝网页发来的请求，动作只接受 POST，每个请求都带上本次运行的令牌——取自应用仅本人可读的 `control-token` 文件，`tools/timbrebox-ctl` 会自动读取）：

- **Claude Code** 对自然语言请求自动调用 `timbrebox-control` skill（"播放周杰伦的歌"、暂停、
  下一首、音量、随机、队列……）；流程是 search → `play-ref` → `status`。
- **Codex CLI** 及任意本地脚本通过 `tools/timbrebox-ctl <cmd>` 或直接 `curl`（带上 `X-TimbreBox-Token` 头）访问 `127.0.0.1`
  上的同一 API。
- 这些是 `timbrebox-ctl` 子命令 / HTTP 路径，**不是** slash 命令——唯一的 slash 命令是
  `/timbrebox-control`，绝不敲裸 `/status`。
- 项目 skill 在**会话启动时**枚举——新增或改动 skill 后需重开会话（重新打开仓库）才会加载并能自动触发。
- 只控制那一个运行实例，绝不启动、构建或修改应用。完整参考见 `docs/agent-control-api.zh-CN.md`。

## 开发标准（强制，每次修复与开发都适用）

### 工作流：Plan → Review 关联 → 方案 → 选最优 → 实施
1. **Plan**：动手前先安排计划（用 TaskCreate 落地有序、可验证的步骤）。
2. **Review 关联**：读清本次改动点与相关代码的关联——谁调用它、它依赖谁、改动会波及哪些页面 / 契约 / 数据层 / 平台。
3. **思考方案**：给出 2–3 个可选方案与权衡。
4. **选最优**：从方案中挑最优再实施，**禁止跳步直接改**。
5. **实施 + 验证**：`flutter analyze` 与测试通过；**关闭旧 app、启动新构建**做真机验证。
6. 写代码走**研发 / 工程技能**（`gstack-plan-eng-review` 定架构、`gstack-review` 查实现），不为“用技能”引入无关依赖。

### 代码质量
- **单文件 ≤ 800 行**；逼近即拆分为多个高内聚小文件。
- **复用优先**（Rule of Three）：已有组件 / 工具 / 解析器先复用，不重复造轮子。
- 可复用逻辑**抽成函数 / 方法**并跨处调用；杜绝复制粘贴漂移。
- **不写无用解释性代码、无用操作、占位死代码**；KISS，只留必要实现。
- **禁 mock / 硬编码 / 假数据**：数据全从真实来源取，前端只渲染；诚实的加载 / 错误 / 空状态。

### 目录标准（专业分层，按功能/领域而非按类型堆叠）
播放引擎必须按「端」与「源」解耦分目录：
- `playback/`：平台音频后端、loopback 代理、resolver、source spec —— **与具体来源无关**。
- `sources/<source>/`：每个来源一个目录（`audius` / `internet_archive` / `radio_browser`）；跨源共享的 HTTP 客户端、解析工具放 `sources/_shared/`。
- `catalog/`：来源注册（registry）与聚合搜索 / 分页 / 榜单。
- 在线音源在 `packages/timbrebox_sources`，播放后端在 `packages/timbrebox_playback`，供其他 App 共享：不得引用 App 的界面和文字（它们的文字放在 `SourceStrings`）。
- `state/` `views/` `widgets/` `model/` `design/` 各司其职，高内聚低耦合。

## 不可突破的边界

- 插件可经 `userVariables` 请求用户主动提供配置；本机保护、仅交给该插件，不静默读取浏览器凭据、不记录秘密。匿名临时会话仅驻留内存。额外登录、Cookie 导入或设备能力需显式设计。
- 保留沙箱、出网、凭据与访问控制保护；纳入平台不代表授权 DRM 绕过或未授权付费访问。CommonJS 插件使用现有五端 JS 沙箱，不以签名或桌面进程 IPC 为当前格式前提。可选桌面媒体 RPC 仅调用构建时明确配置并校验的本地工具和固定操作，不提供任意进程 API；工具内部网络属于独立信任边界，不等于 Dart HTTP 出网策略。各分发渠道独立核实，不提前承诺商店通过。
- 桌面 CLI 是一次性控制客户端，不得启动播放器或残留后台进程。
- 未使用的来源、插件、解析器和网络请求必须为零常驻。
- 引用或改写第三方材料前，在本地内部文档记录许可证、固定版本与归属。

## 完成定义

每个实现任务必须包含：范围关联、测试/fixture、失败路径、性能影响、文档更新和
回滚/来源禁用策略（适用时）。任何改变产品范围、音源、权限、IPC 或性能预算的提交，
必须同步更新本地内部规范与相关架构/准入文档。
