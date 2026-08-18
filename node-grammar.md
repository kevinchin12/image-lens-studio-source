# Image Lens Studio 节点语法

## 1. 目标

Studio 的画布不是通用节点编辑器。它要让用户用少量、可理解的对象完成：

> 从参考素材中选择真正需要的视觉信息，补上自己的创作意图，再形成一条可审计、可复用、可继续分支的生成链路。

基准用例：

1. 一张参考图被拆成主体、场景、风格、光线、镜头、材质、构图和渲染模块。
2. 用户只选择场景、风格和镜头。
3. 用户新建一个空白手写模块，输入新的主体、动作或画面意图。
4. 四个模块组成配方并连接生图节点。
5. 每次生成冻结当时的文本、模块版本、Provider、模型和参数，结果成为新的 Image Node。

## 2. MVP 只保留四类画布节点

### Image Node

代表源图片或生成结果。源图片可以分析，结果图片可以再次分析并形成新分支。

Image Node 不把八个分析维度都自动画成独立节点。分析完成后，默认只保留图片；悬停时显示汇总提示词与右侧八类结构化标签，进入标签立即预览对应内容。用户可以把真正需要的标签拖成 Prompt Module Node，也可以先勾选多个标签，再从图片的聚合输出端口直接加入某个 Generator 的折叠配方。

### Prompt Module Node

代表一个可复用的语义片段，而不等同于一整条最终提示词。

MVP 提供两种 role：

- `visual(category)`：来自图片分析或用户指定类别，类别仍是八个视觉维度之一。
- `instruction`：用户手写的主体、动作、意图或补充要求；允许先创建空白草稿。

分析模块与手写模块使用同一个实体。差别记录在 role、provenance 和 evidence 中，不增加“空白提示词”这一新节点类型。

### Recipe / Composer Node

负责模块选择、顺序、主次、启用状态、冲突提示和编译预览。Recipe 是组合的业务真相，Composer 只是它的编辑界面，不是第五种实体。

视觉模块只能进入对应类别槽位；instruction 模块进入有序 instruction 区域。位置不决定文本顺序，Recipe binding 才决定。

### Generator Node

代表一个可反复使用的生成配置：Recipe、Provider、模型、比例、参数和参考素材绑定。点击生成会创建不可变的 `GenerationRecord`；历史 Run 不因上游编辑而改变，输出始终追加为新的 Image Node。

Generator 与 Run 必须在领域模型中分开：Generator 可编辑，Run 是一次已经冻结的执行记录。它们属于同一个“Generation”画布家族，不增加新的可见节点类型。

## 3. 用户可以“直接连到生图”，但底层不能绕过 Recipe

默认快速交互：

1. 用户从 Prompt Module 的输出端口拖线到 Generator，或在源图片上勾选结构化标签，再从聚合输出端口拖到 Generator。
2. Studio 把单个或批量模块写入 Generator 所引用的 Recipe；一次图片直连只形成一次撤销和一次保存。
3. 未物化为节点的同源模块在画布上聚合成一条带数量的 Image → Generator 连线；当某个标签被拖成节点时，该模块自动改为 Image → Module → Generator 投影。
4. 用户可以直接生成，也可以继续拖出模块，在画布上细调和复用。

图片在直接连接中只是批量选择代理，不是新的业务边，也不是参考图片 binding。两条路径的 canonical 关系始终是：

```text
Prompt Module → Recipe → Compiled Prompt Snapshot → Generation Run
```

不允许 Generation 自己维护另一份隐式长 Prompt，否则排序、冲突、Provider 适配、复用和历史回溯都会失去统一承载对象。

## 4. Typed ports 与连接规则

| 来源 | 目标 | 语义 | 数量 |
|---|---|---|---|
| Image | Analysis action | 生成分析快照与视觉模块 | 一对多 |
| Image 的已选分析模块（UI 代理） | Recipe visual slots | 批量加入对应结构化提示词 | 多个 |
| Prompt Module | Recipe visual slot | 同类别视觉片段 | 多个 |
| Instruction Module | Recipe instruction input | 手写创作意图 | 多个且有序 |
| Recipe | Generator prompt input | 编译后的 Prompt | 严格一个 |
| Image | Generator reference input | 带角色的参考素材 | 多个 |
| Generator / Run | Image | 生成结果谱系 | 多个 |

连接校验：

1. 只允许 output → input。
2. value type 必须兼容。
3. visual category 必须和 Recipe slot 一致。
4. 单值端口拒绝第二条连接，多值端口拒绝重复 binding。
5. live dependency 必须保持 DAG；历史 lineage 不参与实时循环检测。
6. 删除连线只移除引用，不删除原始模块或历史快照。

## 5. 连线是业务关系的投影，不是第二份真相

MVP 不保存任意 `CanvasEdge` 作为独立业务状态。

- Module → Recipe：由稳定 `RecipeInputBinding` 派生。
- Recipe → Generator：由 Generator 的 `recipeID` 派生。
- Image → Module：由模块的 source Asset / Analysis Snapshot 派生。
- Run → Result Image：由 Asset 的 source Generation ID 派生。

画布可以统一投影为 `GraphEdge` 来渲染、命中和高亮，但 Edge 只引用上述 semantic reference，不能再拥有一份会漂移的模块顺序或编译语义。

## 6. 参考素材的角色放在 Binding 上

一张图连接 Generator 时必须说明它负责什么，而不是模糊地“参考这张图”。首批角色候选：

- `identity`
- `environment`
- `style`
- `composition`
- `palette`
- `structure`

角色属于 `GeneratorAssetBinding`，不是额外的“参考图角色节点”。同一张图片可以以不同角色连接到不同 Generator。

这也使文字和图片能明确分工：参考图负责外观与结构，Prompt Module 负责用户想改变的主体、行为、镜头或意图。

## 7. 必须提前补齐的领域模型

### PromptModule

- 增加 `role: visual(category) | instruction`。
- 手写模块使用 `evidence = userProvided`。
- 空白 instruction 可作为草稿存在，但编译时跳过并提示。
- 内容更新必须增加 revision。

### Recipe

- 增加 revision。
- 使用有稳定 ID 的 `RecipeInputBinding` 表达 module、role/category、order、priority 和 enabled。
- Recipe 尽量保持模型无关。

### CompiledPromptSnapshot

不能只保存 module ID。必须冻结：

- Recipe revision 与 compiler version。
- 每个模块的 ID、revision、role/category、resolved content、evidence 和来源。
- Provider / model target。
- base text、final text、warnings 和 input fingerprint。

### Generator 与 GenerationRecord

- `Generator`：可编辑配置与连接，拥有 Recipe、Provider、模型、参数和参考素材 binding。
- `GenerationRecord`：一次冻结的请求、状态、错误、重试关系和输出 Asset。
- 重试创建新 Record，不覆盖旧 Record。

## 8. 哪些东西现在不要做成节点

- AnalysisSnapshot、CompiledPromptSnapshot、JobRecord。
- Provider、模型、比例、seed、变体数等单次参数。
- Image 内的八类 chip、Recipe slot、Prompt preview、结果缩略图。
- Port、连线、reroute point、selection。
- Group、Frame、便签；这些以后可以是纯组织 UI，但不能参与编译。
- 任意 processor、condition、switch、loop 或脚本节点。

原则：只有当一个对象需要被用户独立创建、复用、连接、保存和追溯时，才升级成一等节点。

## 9. 后续候选节点与升级门槛

### Region / Mask

只有当一个区域或蒙版需要被多个生成操作复用时，才成为节点；否则只是 Image 的子选择。

### Palette / Look

只有当色板需要跨图片、Recipe 和 Generator 复用，并且 Provider 能稳定接收时，才升级为 Module 节点；否则是分析结果或 Inspector 控件。

### Compare / Select

先作为结果区的比较模式。只有当“接受哪个结果”必须成为后续分支的持久化决策时，再引入 Selection 实体或节点。

### Parameter Preset

先放在 Generator Inspector。只有用户反复跨多个 Generator 共享同一组参数时，再升级为可连接 preset。

### Edit / Upscale

等 Image → Edit → Image 的任务真实出现后，再判断是否作为独立操作节点。它不应在当前图片生成闭环之前进入 MVP。

## 10. 实施顺序

1. PromptModule role 与空白 instruction 草稿。**已完成。**
2. Recipe revision、稳定 binding 与 typed connection validation。**已完成。**
3. Generator 可编辑实体，与 GenerationRecord 分离。**已完成。**
4. Module 进入 Generator 的折叠 Recipe 交互。**已完成：新建时可自动连接，支持画布端口拖线、节点内菜单与右键菜单添加/移除。**
5. CompiledPromptSnapshot 完整冻结输入文本与 revision。**已完成。**
6. 参考图片 typed role binding。**领域模型、Graph Projection 与图片/Generator 节点内 UI 已完成。**
7. 用真实工作流验证后，再决定 Region、Palette、Compare 或 Preset 是否升级为节点。
