import ImageLensCore
import ImageLensProviders
import SwiftUI

struct WorkspaceInspectorView: View {
    let session: WorkspaceSession
    @State private var isStorageManagementPresented = false

    var body: some View {
        Form {
            Section("工作区") {
                LabeledContent("名称", value: session.title)
                LabeledContent("缩放", value: "\(Int((session.viewport.scale * 100).rounded()))%")
                LabeledContent("素材", value: "\(session.workspace.assets.count)")
                LabeledContent("画布对象", value: "\(session.workspace.canvasNodes.count)")
                Button {
                    isStorageManagementPresented = true
                } label: {
                    Label("管理项目存储…", systemImage: "externaldrive")
                }
                .disabled(!session.isReady)
            }

            if session.selectedNodeIDs.count > 1 {
                Section("多选") {
                    LabeledContent("已选择", value: "\(session.selectedNodeIDs.count) 个节点")
                    Text("拖动其中任一选中节点可整体移动；按 Delete 可从画布批量移除。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let module = session.selectedPromptModule {
                Section("提示词模块") {
                    LabeledContent("角色", value: roleTitle(for: module))
                    if let sourceAssetID = module.sourceAssetID,
                       let source = session.asset(for: sourceAssetID) {
                        LabeledContent("来源", value: source.displayName)
                    }
                    LabeledContent("证据", value: evidenceTitle(module.evidence))
                    TextEditor(
                        text: Binding(
                            get: { session.promptModule(for: module.id)?.content ?? "" },
                            set: { session.updatePromptModuleContent(id: module.id, content: $0) }
                        )
                    )
                    .font(.body)
                    .frame(minHeight: 110)
                    .accessibilityLabel("提示词内容")

                    Text("反推与结构化提示词暂未接入生图节点。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                }
            } else if let textBlock = session.selectedTextBlock {
                Section("备注") {
                    TextEditor(
                        text: Binding(
                            get: { session.textBlock(for: textBlock.id)?.text ?? "" },
                            set: { session.updateTextBlock(id: textBlock.id, text: $0) }
                        )
                    )
                    .font(.body)
                    .frame(minHeight: 110)
                    .accessibilityLabel("备注内容")
                    Text("备注只用于整理画布，不参与图片分析或生成。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let generator = session.selectedGenerator {
                let isVideo = generator.mediaKind == .video
                Section("\(isVideo ? "视频" : "图片")生成节点") {
                    let target = session.effectiveGenerationTarget(for: generator)
                    LabeledContent("比例", value: generator.parameters.aspectRatio)
                    if isVideo {
                        LabeledContent(
                            "时长",
                            value: "\(generator.parameters.videoDurationSeconds) 秒"
                        )
                    }
                    LabeledContent(
                        "生成数量",
                        value: isVideo
                            ? "1 个"
                            : "\(GenerationParameters.normalizedVariationCount(generator.parameters.variationCount)) 张"
                    )
                    LabeledContent(
                        "服务",
                        value: (isVideo
                            ? VideoGenerationModelCatalog.provider(id: target.providerID)?.displayName
                            : ImageGenerationModelCatalog.provider(id: target.providerID)?.displayName)
                            ?? target.providerID.rawValue
                    )
                    LabeledContent(
                        "模型",
                        value: isVideo
                            ? VideoGenerationModelCatalog.model(
                                providerID: target.providerID,
                                modelID: target.modelID
                            )?.displayName ?? target.modelID
                            : ImageGenerationModelCatalog.model(
                                providerID: target.providerID,
                                modelID: target.modelID
                            )?.displayName ?? target.modelID
                    )
                    Text("提示词、比例、参考素材和生成操作都可直接在画布节点中完成。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("提示词") {
                    TextEditor(
                        text: Binding(
                            get: { session.generator(for: generator.id)?.promptText ?? "" },
                            set: { session.updateGeneratorPrompt(id: generator.id, text: $0) }
                        )
                    )
                    .font(.body)
                    .frame(minHeight: 120)
                    .accessibilityLabel("\(isVideo ? "视频" : "图片")生成提示词")
                }

                if !generator.assetBindings.isEmpty {
                    Section("参考素材") {
                        ForEach(generator.assetBindings) { binding in
                            if let asset = session.asset(for: binding.assetID) {
                                HStack {
                                    Text(asset.displayName)
                                    Spacer()
                                    Text(referenceRoleTitle(binding.role))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

            } else if let asset = session.selectedAsset {
                Section("选中素材") {
                    LabeledContent("名称", value: asset.displayName)
                    LabeledContent("类型", value: asset.mimeType)
                    LabeledContent("状态", value: asset.state.rawValue)
                    Text(
                        asset.isVideo
                            ? "视频可在画布节点中播放，也可连接到支持视频参考的生成模型。"
                            : "分析、重试、结果展开和参考素材连接已移到图片节点。"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("当前阶段") {
                    Label("图片与视频导入已接入", systemImage: "checkmark.circle")
                    Label("画布是主场景", systemImage: "square.grid.3x3.square")
                    Label("反推是图片节点的一项能力", systemImage: "viewfinder")
                        .foregroundStyle(.secondary)
                }
            }

            Section("服务") {
                LabeledContent("Gemini Key", value: session.providerSettings.hasAPIKey ? "已存入钥匙串" : "未配置")
                SettingsLink {
                    Label("打开服务设置", systemImage: "gearshape")
                }
            }

            if let statusMessage = session.statusMessage {
                Section {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .sheet(isPresented: $isStorageManagementPresented) {
            ProjectStorageManagementView(session: session)
        }
    }

    private func roleTitle(for module: PromptModule) -> String {
        switch module.role {
        case .visual(let category): category.displayName
        case .instruction: "创作指令"
        }
    }

    private func referenceRoleTitle(_ role: GeneratorAssetRole) -> String {
        switch role {
        case .general: "整体参考"
        case .identity: "主体身份"
        case .environment: "场景环境"
        case .style: "风格"
        case .composition: "构图"
        case .palette: "色彩"
        case .structure: "结构"
        }
    }

    private func evidenceTitle(_ evidence: PromptEvidence) -> String {
        switch evidence {
        case .observable: "可观察"
        case .inferred: "含推断"
        case .userProvided: "用户补充"
        }
    }

    private func compileWarningTitle(_ warning: CompileWarning) -> String {
        switch warning {
        case .missingCategory(let category): "缺少：\(category.displayName)"
        case .multipleModules(let category, let count): "\(category.displayName)包含 \(count) 个模块，将按主次合并"
        case .duplicateText(let category): "\(category.displayName)包含重复文本，已去重"
        case .missingModule: "配方引用的模块已不存在"
        case .emptyModule: "空白模块已跳过"
        case .roleMismatch: "模块角色与配方槽位不匹配"
        }
    }
}
