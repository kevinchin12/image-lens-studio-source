import ImageLensProviders
import SwiftUI

struct ProviderSettingsView: View {
    @State private var settings = ProviderSettingsStore.shared
    @State private var saveError: String?

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Google Gemini") {
                TextField("Base URL", text: $settings.baseURLString)
                SecureField("API Key", text: $settings.apiKey)
                LabeledContent("分析模型") {
                    HStack(spacing: 8) {
                        TextField("模型 ID", text: $settings.analysisModel)
                            .multilineTextAlignment(.trailing)

                        Menu {
                            ForEach(GeminiAnalysisModelCatalog.models, id: \.modelID) { model in
                                Button {
                                    settings.analysisModel = model.modelID
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(model.displayName)
                                        Text(model.summary)
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .help("选择已验证的 Gemini 分析模型")
                    }
                }
                Toggle("同时生成中文模块", isOn: $settings.includeChinese)
            }

            Section("图片生成默认值") {
                Picker("图片生成模型", selection: $settings.generationModel) {
                    if ImageGenerationModelCatalog.model(
                        providerID: ImageGenerationModelCatalog.geminiProviderID,
                        modelID: settings.generationModel
                    ) == nil {
                        Text("自定义 · \(settings.generationModel)")
                            .tag(settings.generationModel)
                    }
                    ForEach(ImageGenerationModelCatalog.geminiModels, id: \.modelID) { model in
                        Text(model.displayName)
                            .tag(model.modelID)
                    }
                }

                Text("只影响之后新建的生图节点；画板上已有节点会继续使用各自保存的模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("数据边界") {
                Text("点击“拆解”或“生成”后，所选图片、参考图与提示词会发送到你配置的 Gemini API。工作区不会保存 API Key；密钥只进入 macOS 钥匙串。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("保存设置") {
                    Task {
                        do {
                            try await settings.save()
                            saveError = nil
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)

                if let status = settings.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 500)
        .task { await settings.loadCredentialIfNeeded() }
        .alert("无法保存服务设置", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好") { saveError = nil }
        } message: {
            Text(saveError ?? "未知错误")
        }
    }
}
