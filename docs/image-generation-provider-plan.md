# 生图服务扩展规划

## 这轮落地

- 生图节点自己保存 `providerID + modelID`，并以此作为实际请求目标。
- Google Gemini 首批提供三个当前稳定模型：Nano Banana 2 Lite、Nano Banana 2、Nano Banana Pro。
- 设置中的模型只作为“新建生图节点默认值”，不会批量改写已有节点。
- 生成记录继续冻结本次使用的服务和模型，因此删除节点或更改默认值后历史仍可追溯。
- 未知或旧模型 ID 保持原样，不静默替换；旧工作区的 `unconfigured` 节点首次使用时才采用当前默认值。

## 服务抽象

`ImageGenerationRequest` 是统一请求边界，包含目标服务、模型、提示词、参考图、比例和按命名空间保存的服务参数。每个平台实现 `ImageGenerationProvider`，画布与工作区数据不直接依赖某个平台的 SDK。

后续服务参数统一使用带命名空间的键，例如：

- `gemini.imageSize`
- `gemini.useGoogleSearch`
- `openai.quality`
- `replicate.version`

这样新增服务时无需修改工作区主结构，也不会让不同平台的同名参数互相污染。

## 后续阶段

### P1：Gemini 完整能力

- 从兼容中的 `generateContent` 生成链路迁移到 Google 当前推荐的 Interactions API。
- 加入输出尺寸选择，并按模型能力显示 1K、2K、4K 或 512。
- 大图和较多参考图改走 Files API，保留 20 MB 内联请求保护。
- 多轮编辑保存 `previous_interaction_id`，把“继续改这张图”变成工作流能力。

### P2：多平台服务中心

- 设置页由单一 Gemini 表单升级为“服务列表 + 服务详情 + 新节点默认值”。
- 凭证按 `provider/profile` 分开存入钥匙串，删除连接只让相关节点显示“服务未配置”，不删除节点和历史。
- 引入 Provider Registry 负责服务发现、能力查询和客户端创建；节点只消费统一接口。
- 模型目录区分内置稳定模型、服务端刷新模型和自定义模型 ID。

### P3：跨平台工作流

- 模型选择器按服务分组，并根据比例、参考图数量和能力显示可用性原因。
- 生成历史展示当次服务、模型和关键参数，支持按服务/模型筛选。
- 提供显式的“迁移节点到另一模型”，迁移前显示不兼容参数；不做静默降级或自动丢弃参考图。

## 数据与迁移原则

- 节点目标是执行真相；全局设置只负责新节点默认值。
- 生成记录是不可变快照，不跟随节点后续修改。
- 复制节点保留目标模型；图片仍复用原有 Asset ID，不复制二进制数据。
- 新服务和自定义模型使用开放字符串 ID，旧工作区不需要 schema 升级。
- 模型不可用、凭证缺失或参数不兼容时明确报错，不静默切换模型。

## 官方依据

- Gemini 图片生成与模型能力：https://ai.google.dev/gemini-api/docs/image-generation?hl=zh-cn
- Interactions API：https://ai.google.dev/api/interactions-api?hl=zh-cn
- Gemini 模型目录：https://ai.google.dev/gemini-api/docs/models?hl=zh-cn
