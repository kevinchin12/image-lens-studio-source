# 关键决策

## D-001：新建 Studio 工程，不在旧 App 上演进

状态：已决定。

Studio 在当前项目目录中建立全新 SwiftPM 工程。旧 App 保持不动，不迁入其窗口、UI、历史、设置、生命周期和单图状态。

## D-002：旧 App 只借鉴反推提示词逻辑

状态：已决定。

只提炼旧 App 的八维视觉分析 Prompt、严格 JSON Contract 和必要的解析样本。截图反推是 Studio 的 Import / Analysis 分支，不是产品主体。

## D-003：无限空间、有限语法

状态：已决定用于 MVP。

提供平移缩放和空间组织，但只允许 Image、Module、Recipe、Generation Run 四类核心对象，不复制通用白板工具栏。

## D-004：先 SwiftPM，后薄 Xcode Host

状态：已决定。

Phase 0–4 使用 SwiftPM 拆可测试 targets。到外部 Beta、Sandbox、文件类型、签名公证和 UI Test 阶段再引入 Xcode App Host。

## D-005：版本化 Workspace 包优先

状态：已决定用于 MVP。

使用 `manifest.json + assets + thumbnails`，原子保存并明确 schemaVersion；SQLite/SwiftData 留到增量写入或跨项目查询成为真实需求时。

## D-006：混合 SwiftUI 画布

状态：已决定用于第一版。

SwiftUI Canvas 绘制网格和边，交互节点保持 SwiftUI View；AppKit 只处理系统级或精确事件边界。没有 Instruments 证据前不上 Metal。

## D-007：先确定性编译器

状态：已决定用于 MVP。

模块排序、去重、冲突与 Provider 适配由可测试规则完成。生成时冻结 Prompt Snapshot，最终文本手改记录为 Override。

## D-008：视觉方向尚未选择

状态：待 Kevin 选择。

正式视觉方向尚未选择。工程阶段先使用系统原生组件搭建不承诺最终外观的功能壳层；正式 UI 仍需三方向探索后选择。

## D-009：正式代码位置已确定

状态：已决定。

正式源码位于 `/Users/kevinchin/Documents/Codex/Projects/image-lens-studio/`。旧源码 `/Users/kevinchin/Documents/Playground/macos/` 仅作为只读领域参考，不与新工程形成共享源码或长期分叉。

## D-010：普通图片导入先于截图入口

状态：已决定并完成第一段实现。

普通文件导入是 Asset Source 的基准链路：素材复制、内容哈希去重、Workspace 持久化与 Image Node 创建已经接通。截图后续只负责产生另一种源文件，并复用同一套 Asset、CanvasNode、Analysis 和保存流程。

## D-011：MVP 保持四类节点，其他能力优先成为 typed value 或 binding

状态：已决定。

MVP 只保留 Image、Prompt Module、Recipe 和 Generation 四类节点。分析快照、编译快照、Job、参数、端口和连线不升级为一等节点。参考素材的 identity、environment、style、composition、palette、structure 等角色存放在 binding 上。

## D-012：允许直接拖入 Generator，但 canonical 关系必须经过 Recipe

状态：已决定。

用户把视觉模块或手写 instruction 拖到 Generator 时，Studio 自动创建一个可展开的折叠 Recipe。Generation 不维护第二份隐式长 Prompt；每次运行仍由 Recipe 经确定性 Compiler 生成完整快照。

## D-013：Generator 与 GenerationRecord 分离

状态：已决定并完成领域模型与第一版 UI。

Generator 是可编辑、可复用的画布配置节点；GenerationRecord 是一次不可变的实际运行。修改上游只使 Generator 变为待重新编译，不修改历史 Run。重试创建新 Record，生成结果持续追加为 Image Node。

## D-014：MVP 只提供 Gemini 原生 Provider

状态：已决定并实现。

分析和生图共享 typed HTTP transport、官方 HTTPS Base URL 与一份 Keychain credential。模型名保持可编辑，不把当前模型名视为永久能力。MVP 不暴露模糊的 OpenAI Compatible 万能入口；新增 Provider 必须有独立 contract、capability 与 fixture。

## D-015：截图先复用系统剪贴板，不建立第二套工作流

状态：已决定并实现 MVP 入口。

用户可用 macOS 系统截图快捷键把区域写入剪贴板，再由 Studio 的“粘贴图片”进入与文件导入相同的 Asset、Analysis、Canvas 和 Persistence 链路。全局多屏截图 overlay 延后，不让截图分支重新主导 App 架构。

## D-016：主流程操作回到画布，Inspector 退为详情与编辑

状态：已决定并实现第一版。

连接、比例选择、参考图绑定、分析、重试与生图都应在对应节点或其右键菜单中完成。Inspector 继续承载工作区状态、来源、证据、长文本编辑和编译详情，但不再是主操作入口。画布使用滚轮/触摸板双指或空格拖拽平移，普通拖拽留给节点与连线。

## D-017：分析结果采用渐进披露，不自动铺满画布

状态：已决定并实现第一版。

图片分析完成后，图片静止状态不显示提示词 chrome。悬浮图片时才显示底部汇总提示词和右侧八类结构化标签；汇总框悬浮后向下展开完整文本，鼠标进入单个结构化标签时立即淡入预览该类内容，移开后淡出。预览浮层保持固定视图层级，不能因为出现时重建标签命中区域而触发 hover 离开；整列标签统一维护 chrome 悬停状态，避免标签之间切换时误收起。分析结果实体仍完整持久化，但只有用户把标签拖到画布时，对应结果才成为可见 Prompt Module Node。

## D-018：画布选择是临时 UI 状态，批量移动是一次可撤销命令

状态：已决定并实现第一版。

单选、多选、框选和主选节点不写入 Workspace manifest；主选只负责驱动 Inspector。普通框选替换选择，Shift 点击切换单项，Shift 框选追加。拖动已选节点时冻结整组 ID，所有节点及关联连线共享一份临时 view translation；松手后才换算为 world 坐标并以一次批量命令落盘，因此一次拖动只产生一个 Undo 与一次自动保存。

## D-019：画布输入序列必须有唯一所有者

状态：已决定并实现第一版。

滚轮事件归画布平移；空格按下后，直到对应鼠标抬起为止，该拖动序列只归平移工具，不得再触发框选或节点拖动。Delete、Command–A、Esc 与空格由画布桥接层消费；不在文本编辑器中且没有绑定操作的普通按键静默忽略，Command/Control 系统快捷键继续进入 AppKit responder chain。

## D-020：图片内容与节点信息分层呈现

状态：已决定并实现第一版。

Image Node 的持久化 frame 继续代表图片像素区域，也是连线锚点和框选命中区域。文件名与来源以无底衬文字放在图片上方；底部汇总框与右侧八类标签在视图层围绕图片渲染，不覆盖图片，也不改写已有画布坐标。除顶部文字外，信息 chrome 默认隐藏，只在图片、汇总框或标签的悬浮岛内显示。

## D-021：结构化提示词标签是画布节点的直接拖拽源

状态：已决定并实现第一版。

八类标签使用稳定顺序；本次分析缺失的分类仍占位但不可拖动，避免每张图片的空间词汇跳动。拖动有内容的标签时先显示轻量跟手预览，落到画布后创建对应 Prompt Module Node；若该模块已经在画布上，则移动既有节点，不复制领域实体。标签拖动独占当前输入序列，不触发图片拖动、框选或空格平移。

## D-022：手写提示词就地编辑，生图一击发起

状态：已决定并实现第一版。

空白 instruction 模块必须在画布节点内直接输入，不再要求用户转到 Inspector。生图节点的主按钮与右键操作不显示重复确认弹窗，点击后立即占用全局唯一 Generation 通道并进入可取消的运行状态；费用与数据发送边界保留为常驻说明，而不是每次操作的阻断确认。同步占用通道用于防止连续点击或两个生图节点同时发起重复 Provider 请求。

## D-023：捏合缩放围绕固定手势锚点，世界内容与屏幕控件分层

状态：已决定并实现第一版。

触摸板 magnify 事件按连续增量直接更新 viewport，不吸附离散档位，也不使用动画追赶。一次捏合从开始到结束冻结同一个指针锚点，使锚点下的世界坐标保持不变，并限制在 20%–400%。Prompt、Generator、图片信息、结构化标签和连接端口使用显式的 `base × viewport.scale` 画布度量；画布中的菜单触发器使用同样度量的 plain Button，弹出内容再进入固定可读的屏幕空间，避免原生 Menu 的最小尺寸和缩放后命中区域错位。底部缩放控件、拖拽跟手预览与悬浮详情等瞬时屏幕 UI 保持固定可读，且不对整个节点使用 `scaleEffect`，避免破坏文本输入、命中测试和节点拖动坐标。

## D-024：节点复制克隆编辑语义，不复制重型素材

状态：已决定并实现第一版。

Command–C / Command–V 复制当前画布选集并保留组内相对位置。Prompt Module、Recipe 与 Generator 获得新 ID，组内 binding 自动重映射，确保副本可以独立编辑；Image Node 只获得新的 CanvasNodeID，继续引用原 AssetID。原图、缩略图、分析快照、编译历史、生成记录和任务不会随复制重复写入，Workspace 只增加必要的实体与画布 JSON。重复 Asset occurrence 的来源连线按空间距离选择最近节点，避免副本覆盖原节点的连线锚点。

## D-025：生图提示词展开直接改变世界节点尺寸

状态：已决定并实现第一版。

Generator 默认展示七行编译提示词；内容超过七行时显示“展开完整提示词”。展开高度根据节点世界宽度与文本排版估算并写回 CanvasNode frame，左上角不动、节点向下增高，因此连线中点、框选、拖动、命中与 culling 使用同一份几何数据。显式展开或收起进入 undo；已展开状态下的 Prompt 内容变化只同步高度，不额外污染 undo 历史。

## D-026：左栏只承载素材库与生成历史

状态：已决定并实现第一版。

Recipe 是 Generator 的内部提示词组合，不再作为左栏一级入口；Generator 配置本身也只在画布编辑。左栏保留“素材库”和“生成历史”：素材点击后定位已有画布实例，缺少实例时放回画布；生成历史展示不可变的实际运行，并定位其输出素材或源生图节点。

## D-027：从画布移除不删除素材本体

状态：已决定并实现第一版。

CanvasNode 是素材或配置在画布上的 occurrence。对 Image Node 和来源图片派生的 Prompt Module，Delete、工具栏和节点右键菜单只移除 occurrence，Asset、分析结果和文件继续留在素材库，可再次放回画布。没有来源图片的手写 Prompt Module 与 Generator 属于画布工作流配置，遵循各自的最后 occurrence 清理规则。MVP 暂不提供不可恢复的素材级删除；未来应以废纸篓或明确的引用检查实现，而不是复用画布删除动作。

## D-028：图片四周信息锚定实际显示像素区域

状态：已决定并实现第一版。

图片使用真实宽高比在持久 frame 内 aspect-fit。顶部文件信息、底部汇总提示词和右侧八类标签分别从 displayed image rect 推导，不能以固定 320×240 容器作为视觉锚点。外层 shell 在解码前后保持稳定，选择与持久化继续使用 frame；所有进入或离开图片的连线则锚定 displayed image rect 的左右边缘，不能锚定隐藏标签栏或 aspect-fit 容器的空白区域。9:16、1:1 与 16:9 几何均需通过不相交及锚点回归测试。

## D-029：生成结果固定可见宽度，高度跟随真实像素比例

状态：已决定并实现第一版。

生成结果不再统一塞入 320×240 容器后 aspect-fit，而是把真实 PixelSize 写入 Asset，并将 Image Node 固定为 320 世界单位宽，高度按实际像素比例计算。同批多图按行内最大高度推进，避免竖图与横图网格互相覆盖。启动时为旧生成素材补齐尺寸并幂等迁移既有节点；素材库重新插入生成图也复用同一尺寸策略。

## D-030：素材库单击只查看，插入画布必须是明确动作

状态：已决定并实现第一版。

素材行显示真实缩略图；单击只选择素材并打开左栏底部预览，不移动视口、不创建 CanvasNode，也不增加 Undo。预览提供“插入画布”；已有实例时同时提供“在画布中查看”和“再插入一处”。生成历史也不再隐式恢复已移除结果，而是定位已有实例或把结果交给素材预览继续决定。

## D-031：删除最后一个生图节点实例同步删除可编辑配置

状态：已决定并实现第一版。

Generator 与图片 Asset 的所有权不同：图片可离开画布继续留在素材库，Generator 则是画布上的可编辑配置。删除最后一个 Generator occurrence 时同步删除 Generator；其 Recipe 仅在没有剩余 Generator、GenerationRecord 或 CompiledPromptSnapshot 引用时删除。生成历史、编译快照、结果 Asset 永远保留。启动时会清理旧版本 occurrence-only 删除留下的孤儿 Generator；结构删除立即保存，窗口进入非活动状态时再次 flush，避免快速退出后回生。

## D-032：文本编辑 first responder 优先于画布键盘路由

状态：已决定并实现第一版。

只要可编辑 TextField / TextView 仍是窗口的 first responder，Command–A / C / V / X / Z、Delete、Esc 与空格都属于文字编辑，不因指针移出输入框而转交画布。SwiftUI 侧栏行不保证成为 AppKit first responder，因此画布桥接层还必须记录最后一次鼠标按下是否位于画布；只有画布 responder 与显式画布交互范围同时成立，才执行节点快捷键。点击素材行会清空画布选择，侧栏或工具栏范围内的 Delete 不得作用于旧选择，也不得进入空 responder chain 触发提示音。滚轮和捏合仍按指针范围路由，不受文字焦点影响。

## D-033：本地事件监听的 nil 必须保持“已消费”语义

状态：已决定并实现第一版。

`NSEvent.addLocalMonitorForEvents` 的处理闭包返回 `nil` 代表事件已完成处理、不得继续派发。不能用 `self?.handle(event) ?? event` 包装一个本身返回 Optional 的 handler，否则被消费的事件会被原事件复活，造成画布操作已经生效后 `NSWindow keyDown` 仍调用 `NSBeep`。监听器必须在 weak self 失效时才返回原事件；self 存在时直接返回 handler 的 Optional 结果。键盘焦点由真实 AppKit responder 决定，已消费的 keyDown 与 keyUp 成对截断。

## D-034：生成结果组是持久化展示容器，不是第五类节点

状态：已决定并实现第一版。

每个生图节点的新增结果自动进入对应 `CanvasGenerationGroup`，按固定可见宽度的两列网格持续追加。结果组只持有成员 CanvasNodeID、世界坐标、列数、折叠状态和可失效的来源 GeneratorID，不参与 Prompt 编译，也不扩张 `CanvasNodeKind` 的有限语法。展开时子图片保持真实比例；折叠时子节点只在视图层隐藏，素材、谱系与画布实例继续存在。拖动组标题或任一成员会以一次 Undo 整组移动，连线只保留生图节点到结果组的一条表达。删除最后一个 Generator occurrence 后，结果组保留但解除 GeneratorID，变成独立展示分组，不留下悬空引用。删除结果组仅移除成员 occurrence；Asset、GenerationRecord 与磁盘图片继续保留。复制完整结果组时复用原 AssetID，只克隆轻量节点和组元数据，避免工作区数据库随复制重复写入图片与历史。

## D-035：提示词拆解只属于导入原图，生成结果保持纯图片

状态：已决定并实现第一版。

`Asset.kind == .source` 的导入原图继续拥有顶部文件信息、底部汇总提示词、右侧八类结构化标签以及分析、重试和拖出 Prompt Module 的入口。`Asset.kind == .generated` 的生成结果只渲染图片本身，不显示这些 chrome，也不再发起新的提示词分析；右键菜单仍保留参考图连接、Finder 定位和从画布移除。生成图 hover 不改变节点层级，结果组布局也不再为隐藏的提示词与标签预留空白。

## D-036：源图片是结构化提示词集合的批量连接代理

状态：已决定并实现第一版。

用户可在一张已分析的源图片上勾选多个非空结构化标签，再从“数量 + 箭头”端口拖到 Generator。勾选状态只存在于当前画布交互，一次只作用于一张图片；Esc、点击或框选空白处会清除，成功连接后也会清除。图片本身不创建新的持久 Edge，也不复用 `GeneratorAssetBinding`：底层仍批量写入同一个 Recipe 的 `RecipeInputBinding`，按 module ID 去重，一次操作只增加一次 Recipe revision、一次 Undo 和一次保存。

未在画布物化的已绑定模块按 `(sourceAssetID, generatorID)` 聚合投影为一条带数量的靛蓝 Image → Generator 连线。任一标签拖成 Prompt Module Node 后，该模块退出聚合线，改由既有 Image → Module → Generator 连线表达；其余未物化模块继续聚合。生成结果图片不提供这条入口。

## D-037：图片像素尺寸是显示与连线几何的唯一真相源

状态：已决定并实现第一版。

`Asset.pixelSize` 同时驱动图片的 aspect-fit 显示区域、四周信息位置和左右连线锚点，视图层不得再用异步解码得到的 `NSImage.size` 单独计算比例。文件、剪贴板与生成结果导入时通过 ImageIO 元数据读取显示方向修正后的像素尺寸；启动旧工作区时为所有缺失尺寸的 Asset 幂等补齐并保存。旧源图片只补元数据，不改变已有 CanvasNode frame；旧生成结果继续按固定可见宽度规范化 frame。这样方图、横图与竖图在任意缩放下都由同一份持久化几何计算显示和连线，不会因连线层早于图片解码而锚到占位容器。

## D-038：节点显示名按对象类型独立编号并允许就地修改

状态：已决定并实现第一版。

Generator、其内部 Recipe 和生成结果组分别使用“生图 N”“提示词组合 N”“生成结果 N”的独立编号空间，不再由同一个标题互相派生。新建对象按该类型已使用的最大规范编号继续递增；复制规范默认名时生成下一个编号，复制自定义名时依次追加“副本”“副本 2”，避免同名副本和嵌套后缀。旧工作区启动时只修复空名称和重复的规范默认名，保留用户主动设置的同名自定义名称。Generator 与生成结果组标题支持双击或右键就地重命名；空白输入不提交，一次提交只产生一次 Undo 与一次保存，并且显示名变更不增加 Prompt 的语义 revision。

## D-039：可编辑连接是一等交互对象，断连不删除节点

状态：已决定并实现第一版。

画布上可见的 Recipe binding 可作为临时选中对象：连线保留 Canvas 绘制层，同时叠加屏幕空间固定宽度的透明命中区域，避免缩放后难以点击。单击后高亮曲线与端点，并在曲线中段显示“断开”；Delete / Backspace、右键菜单和辅助功能动作执行同一条精确断连事务。Generator 的参考图 binding 虽仍从节点内菜单管理，但复用同一套精确事务。断连只按稳定 binding ID 删除关系，不删除两端节点、Asset、PromptModule 或历史记录；一次操作只写入一次 Undo 快照和一次保存，过期或已删除的 binding 视为无操作。

源图片代理出的聚合连接以 `(sourceAssetID, generatorID)` 为组标识，数量徽标允许逐项断开，也允许将当前组内的 module binding 一次性全部断开；两种操作都可撤销。Image → Module、Generator → Generation Group / Result 等来源和谱系连接只表达事实，不属于可编辑 binding，因此保持只读且不提供断开入口。

## D-040：画布删除按对象所有权区分 occurrence 与工作流实体

状态：已决定并实现第一版。

界面不再把所有动作统称为“从画布移除”。图片、来源图片派生模块和仍有其他 occurrence 的对象继续使用“从画布移除”；删除最后一个 Generator occurrence 使用“删除生图节点…”，并明确保留生成历史和结果图片；删除没有来源图片的手写 Prompt Module 最后一个 occurrence 使用“删除提示词…”，同时从所有活动 Recipe 移除对应 binding 并删除 PromptModule 本体。每个受影响 Recipe 只增加一次 revision，历史 CompiledPromptSnapshot 保持不可变。

Recipe 回收必须把仍存在的 Recipe CanvasNode、Generator、GenerationRecord 和 CompiledPromptSnapshot 都视为引用根。删除 Generator 后，结果组解除 GeneratorID 而不删除成员图片。混合多选使用“删除选中内容…”；所有结构变更仍进入同一个 Undo 快照并立即保存。

启动时的兼容清理采用更保守的三重条件：只删除同时没有来源图片、没有任何画布实例、也没有活动 Recipe binding 的幽灵手写 PromptModule。任一条件不满足都必须保留；该清理不会删除图片 Asset、磁盘图片文件、GenerationRecord、结果组或历史 CompiledPromptSnapshot。

## D-041：关系菜单只从当前画布新增候选

状态：已决定并实现第一版。

生图节点的“参考图”和“提示词”是当前画布关系菜单，不是素材库或 Workspace 全量浏览器。新增候选只来自当前存在 CanvasNode occurrence 的 Asset 或 PromptModule，并分别按 AssetID、PromptModuleID 去重；同一实体在画布上的多个 occurrence 不得产生重复菜单项。未绑定且不在画布的素材或提示词不进入候选，用户必须先通过素材库“插入画布”、拖入图片、新建手写提示词或从图片展开结构化标签。

既有 binding 不因对象离开画布而隐身。已经绑定、后来移出画布的参考图或提示词继续在“已绑定 · 不在当前画布”分组显示，保留角色、类型与断开入口，但不会被自动插回画布。当前画布没有可新增对象时显示作用域明确的空状态，并继续展示离板绑定；右键菜单与节点内 popover 使用同一套候选投影，避免同一关系在两个入口出现不同范围。
