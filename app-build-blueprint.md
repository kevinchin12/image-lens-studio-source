# App 搭建蓝图

## 1. 工程策略

Image Lens Studio 使用全新工程，不在旧 ImageLensMac 上渐进重构。

旧 App 只提供一份经过验证的领域参考：如何把单张图片反推为主体、风格、光线、镜头、环境、材质、构图和渲染八类结构化描述。实现时只提炼它的分析 Prompt、JSON Contract 和必要的响应兼容样本，不复制旧网络 Service、窗口、UI、历史、设置或单图状态。

新工程从以下一级对象开始：

- Workspace
- Infinite Canvas
- Asset
- Prompt Module
- Recipe
- Compiled Prompt Snapshot
- Generation Run / Lineage

截图只是 Asset Import 与 Analysis 的一个分支入口。

## 2. 主窗口与信息架构

主窗口采用桌面级四区结构：

- **左侧资产栏**：来源图、已拆解图、配方、结果、搜索与状态筛选。
- **中央工作台**：可平移缩放的画布，只放 Image、Module、Recipe、Run。
- **右侧 Inspector**：根据选择显示对象详情、模块编辑、编译预览和生成参数。
- **底部上下文动作条**：只呈现当前选择的下一步，例如拆解、加入配方、生成、重试、再次利用。

顶部窗口栏负责项目名、导入、撤销/重做、缩放和保存状态。截图反推在纵向闭环稳定后作为独立 Import Action 接入。

核心交互规则：

- 单击选择，双击编辑。
- 拖入 Recipe 表示引用；Option 拖动才复制独立模块。
- Hover 模块时高亮来源图片与 Recipe 中的引用。
- 新结果只追加，不覆盖。
- 位置用于整理，不用于推断语义关系。
- 每个鼠标动作都需要 Inspector、菜单或键盘的等价路径。
- 状态必须同时有文字或图标，不能只靠颜色。

## 3. SwiftPM 模块边界

继续以 SwiftPM 为主，先拆成五个 target：

### ImageLensCore

Foundation-only。放置 Workspace、Asset、PromptModule、Recipe、Generation、Job、ProviderID，以及 Provider/Repository 协议和确定性 PromptCompiler。

### ImageLensCanvas

世界坐标、camera transform、选择、框选、命中测试、空间索引、viewport culling 和画布命令。不持有 NSImage，只处理 AssetID 与缩略图元数据。

### ImageLensProviders

HTTPTransport、Gemini 和 OpenAI Compatible adapters、typed Codable DTO、错误归一化与 `AnalysisResponseNormalizer`。用脱敏 fixture 锁定当前宽松解析行为。

### ImageLensPersistence

Workspace repository、资产文件、缩略图、迁移链和 Keychain credential store。磁盘、图片解码和缩图都在 actor 内完成。

### ImageLensMac

SwiftUI 窗口、工具栏、资产栏、画布节点、Inspector、设置与菜单栏入口；截图、全局快捷键、文件面板保留窄 AppKit 桥接。

暂不迁为纯 Xcode 工程。到外部 Beta、Sandbox、正式签名/公证、文件类型注册或 UI Test 阶段，再增加薄 Xcode App Host，核心仍由 Swift Package 提供。

## 4. 状态与并发

- `WorkspaceSession: @MainActor @Observable`：当前 Workspace、选择、编辑草稿和 Job 摘要；每个窗口独立。
- `JobCoordinator: actor`：任务、限流、取消、去重和过期结果丢弃。
- `WorkspaceRepository: actor`：原子保存、加载和迁移。
- App 级只共享 Provider registry、credentials、repository 与 WorkspaceRouter。
- 菜单栏截图由 WorkspaceRouter 投递到当前活动 Workspace，不再重建根视图。

任务分 lane：

- Analysis 默认并发 2。
- Generation 默认并发 1，并按 Provider capability 调整。
- Thumbnail 默认并发 2–4。

每个 Job 冻结 asset revision、provider、model 和 prompt schema；返回时校验 revision，避免旧响应覆盖新编辑。生图不自动重试，避免重复计费；分析只对明确的瞬时网络错误有限重试。

## 5. Canonical 数据模型

- `Workspace`
- `Asset`
- `AnalysisSnapshot`
- `PromptModule`
- `Recipe`
- `CompiledPromptSnapshot`
- `CanvasNode`
- `CanvasEdge`
- `GenerationRecord`
- `JobRecord`

`ProviderID` 使用开放字符串，并通过 `ProviderCapabilities` 声明分析、生图、参考图、JSON、比例、变体数等能力，不继续扩大封闭 enum 和 switch。

`ReversePromptResponse` 只作为 Provider DTO，进入 Core 前必须转换为带稳定 ID 和来源的 `PromptModule` 数组，不能成为 Workspace 的 canonical model。

## 6. 持久化

MVP 使用版本化 Workspace 包，不先引入数据库：

```text
Workspace.imagelens/
  manifest.json
  assets/original/
  assets/derived/
  thumbnails/
```

- manifest 必须有 `schemaVersion`。
- 资产使用 SHA-256 去重，只存相对路径和元数据。
- 手势结束后安排保存；连续编辑使用约 500–1000ms debounce。
- 写临时文件后 atomic rename，保存失败保留上一份完整 manifest。
- UserDefaults 只放普通偏好，Keychain 放 API Key。
- 选择、hover 和临时拖动状态放内存或 SceneStorage。
- 解码缩略图使用 NSCache，原图不常驻内存。

当 Workspace 达到 1000–5000 节点、跨项目搜索或增量写入成为真实瓶颈时，再将 Repository 实现换成 SQLite/SwiftData。Apple 的 `ModelContainer` 支持 schema、存储配置与迁移，但不是当前 MVP 的前置条件：<https://developer.apple.com/documentation/swiftdata/modelcontainer>。

若未来需要 Finder 原生双击打开、多文档菜单与文件类型集成，可用 `DocumentGroup` 增加文档式 App Host：<https://developer.apple.com/documentation/swiftui/documentgroup>。

## 7. 画布渲染路线

第一版采用混合 SwiftUI：

- 自己维护世界坐标和 camera transform。
- 触摸板捏合按事件增量围绕手势起点无级缩放；节点字体和画布内度量跟随 camera scale，HUD 保持屏幕尺度。
- SwiftUI `Canvas` 绘制网格、连线、选择框和低交互装饰。
- 可见节点用独立 SwiftUI NodeView 叠加，保留 Inspector、菜单、键盘与无障碍。
- uniform-grid spatial index + viewport culling。
- 原图后台生成 256 / 512 / 1024 缩略图，根据 zoom 选层级。

Apple 明确说明 SwiftUI `Canvas` 是即时 2D 绘制，并不为内部元素提供独立交互和无障碍，因此它不应承担节点本身：<https://developer.apple.com/documentation/swiftui/canvas>。

AppKit 只用于：

- NSStatusItem 和全局快捷键。
- 多屏截图 overlay、精确窗口与文件面板。
- SwiftUI 手势确实冲突时，用薄 NSViewRepresentable 处理滚轮、magnify、modifier、first responder、框选与拖放事件。

只有在 culling 和缩略图缓存后，200 个可见节点 / 400 条边仍不能稳定 60Hz，才考虑 layer-backed NSView / Core Animation。Metal 只在 Instruments 明确证明需要约 1000 个可见缩略图、数千动态边或实时 GPU 图像处理时使用。

## 8. Prompt Compiler

第一版使用确定性编译，不再调用模型黑箱改写整条 Prompt：

1. 按固定类别排序。
2. 清理空值和完全重复项。
3. 保留来源与主次关系。
4. 检查同类别重复、明显矛盾和缺失项。
5. 根据 Provider capability 适配格式。
6. 生成自然语言预览和不可变请求快照。
7. 用户直接编辑最终文本时记录 Override，不静默回写来源模块。

## 9. 实施阶段

### Phase 0：建立新工程基线

- 创建 Core、Canvas、Providers、Persistence、Mac 五个 SwiftPM target。
- 配置统一的 build/run 入口与 Codex Run Action。
- 建立 test targets、系统原生主窗口和 Workspace Session。
- 旧 App 保持不动。

### Phase 1：建立画布与领域内核

- 完成 Workspace、Asset、PromptModule、Recipe 和 GenerationRecord。
- 完成世界坐标、viewport transform、选择与 culling。
- 提炼旧反推逻辑为独立 ReversePrompt Contract 和 typed DTO。
- 实现版本化 Workspace Package 与原子保存。

### Phase 2：核心画布纵切面

- 导入 / 截图生成 Image Node。
- 分析生成八类 PromptModule。
- 模块进入 Recipe，编译 Prompt。
- 生图成为 Run，结果成为新节点。
- Workspace v1、资产仓库、自动保存和最小谱系同步落地。

### Phase 3：多图组合与任务系统

- 多资产并发分析。
- 跨图模块拖拽、复用和 Recipe 分支。
- Job queue、对象级状态、取消和显式重试。
- Workspace Library 与跨项目检索。

### Phase 4：桌面交互与性能

- culling、spatial index、thumbnail pyramid 和缓存。
- 键盘命令、框选、多选、复制粘贴、撤销/重做。
- 两图比较、候选状态与再次拆解。
- 根据真实指标决定是否升级渲染层。

### Phase 5：分发工程化

- 薄 Xcode App Host、asset catalog、Info.plist、entitlements 和文件类型。
- App Sandbox、Keychain、签名、公证与 UI tests。
- SwiftPM 核心模块保持独立可测试。

## 10. 测试与完成门槛

测试层：

- `PromptCompilerTests`：稳定排序、冲突、Provider golden output。
- `ProviderTests`：stub transport、脱敏响应、错误归一化。
- `PersistenceTests`：atomic save、损坏恢复、schema migration。
- `CanvasGeometryTests`：坐标变换、连续缩放锚点、缩放边界、框选、命中和 culling。
- `JobCoordinatorTests`：限流、取消、过期响应和并发顺序。
- 手工集成：实体触摸板捏合手感、权限、多屏截图、Retina 坐标、Keychain 与生成费用边界。

性能门槛：

- 200 个可见节点、400 条边，pan/zoom p95 不超过 16.7ms。
- 1000 节点、2000 条边的 Workspace，冷启动到可交互不超过 1 秒。
- MainActor 不出现超过 8ms 的同步磁盘或图片处理。
- 默认缩略图缓存预算约 256MB，原图不常驻解码。
- 保存中强杀时至少能恢复上一份完整 manifest。
- 所有迁移 fixture 不丢 ID、来源和用户编辑。
- Swift 6 strict concurrency 不新增 warning。

这些数字是工程预算，需用 Instruments 与真实设备验证后调整。

## 11. 第一批不可跳过的安全修复

1. 新工程从第一天只把 API Key 存入 Keychain。
2. Provider 和模型名每次使用前验证，不把当前默认值当作永久可用能力。
3. 图片发往 Provider 前显示清晰的服务方与隐私提示。
4. Workspace 损坏时保留上一份完整 manifest，并报告具体文件。
5. 生图重试必须由用户触发，避免重复计费。

## 12. 开工顺序

产品与工程不应同时跳到“完整画布”。正确顺序是：

1. 完成全新工程的 Phase 0–1，不引入旧 App 架构。
2. 用系统原生外观验证 Workspace 与 Canvas 的交互结构。
3. 生成并选择 Studio 的正式视觉方向。
4. 用选定方向实现 Phase 2 的唯一纵向闭环。
5. 用 5 名目标用户验证，再决定画布自由度和扩展对象。

## 13. 当前实现快照（2026-07-22）

本地 MVP 纵向闭环已完成：文件或剪贴板图片进入持久化 Image Node；Gemini Analysis 通过严格八维 Contract 生成有来源和证据边界的 PromptModule；手写 instruction 与选定视觉模块进入 canonical Recipe；Generation 冻结完整 Prompt Snapshot，写入生成记录和派生资产，并把输出重新放回画布。

画布支持节点拖动、滚轮/双指/空格平移、围绕手势锚点的触摸板无级捏合缩放、谱系连线、最小撤销/重做；画布节点文字与端口随 zoom 同步缩放，HUD 保持屏幕尺度。Inspector 支持比例、参考图 typed role、Provider 隐私/费用说明、对象级状态、取消与显式重试。生图节点一击直接发起，并由单一 Generation 通道同步防止重复请求。普通偏好在 UserDefaults，API Key 只在 Keychain。JobCoordinator 内核提供 Analysis 2 路、Generation 1 路、取消和 stale result 识别。

自动化测试使用 Stub Transport，不携带真实 API Key，也不产生 Provider 费用。正式 Gemini 调用需要使用者在设置中提供自己的密钥；签名、公证、多屏截图 overlay、缩略图金字塔和最终视觉方向仍属于 MVP 之后。

## 14. 节点语法约束

MVP 继续保持 Image、Prompt Module、Recipe、Generation 四类节点，但补齐手写 instruction、typed binding、Generator 与不可变 Run 的区分，以及带角色的参考图片输入。

用户可以把场景、风格、镜头和手写 Prompt 直接拖入 Generator；Studio 会自动创建一个可展开的折叠 Recipe。交互上保持轻量，底层仍统一经过 Recipe 与确定性 Prompt Compiler，不建立隐式旁路。

完整规范见 [node-grammar.md](./node-grammar.md)。
