import ImageLensCanvas
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    let session: WorkspaceSession
    @State private var isFileImporterPresented = false
    @State private var canvasViewportSize = ViewSize.zero

    var body: some View {
        @Bindable var session = session
        let removalPresentation = CanvasRemovalPresentation(session: session)

        NavigationSplitView {
            WorkspaceSidebarView(
                session: session,
                viewportSize: canvasViewportSize,
                selection: $session.selectedSection
            )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            CanvasSurfaceView(
                session: session,
                viewportSize: $canvasViewportSize,
                onImportMedia: { isFileImporterPresented = true }
            )
                .inspector(isPresented: $session.isInspectorPresented) {
                    WorkspaceInspectorView(session: session)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            session.undo()
                        } label: {
                            Label("撤销", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(
                            session.undoDepth == 0
                                || !session.activeAnalysisAssetIDs.isEmpty
                                || !session.activeGenerationGeneratorIDs.isEmpty
                        )

                        Button {
                            session.redo()
                        } label: {
                            Label("重做", systemImage: "arrow.uturn.forward")
                        }
                        .disabled(
                            session.redoDepth == 0
                                || !session.activeAnalysisAssetIDs.isEmpty
                                || !session.activeGenerationGeneratorIDs.isEmpty
                        )

                        Menu {
                            CanvasAddMenuContent(
                                session: session,
                                viewportSize: canvasViewportSize,
                                onImportMedia: { isFileImporterPresented = true }
                            )
                        } label: {
                            Label("添加", systemImage: "plus")
                        }
                        .help("向画布添加内容或操作")
                        .disabled(!session.isReady)

                        Button {
                            Task {
                                await session.importClipboardMedia(viewportSize: canvasViewportSize)
                            }
                        } label: {
                            Label("粘贴素材", systemImage: "clipboard")
                        }
                        .help("从剪贴板导入图片或视频；也可复制 Finder 中的媒体文件")
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                        .disabled(!session.isReady || session.isImporting)

                        Button {
                            session.isInspectorPresented.toggle()
                        } label: {
                            Label("检查器", systemImage: "sidebar.trailing")
                        }
                        .help("显示或隐藏检查器")

                        Button(role: .destructive) {
                            session.removeSelectedNodesFromCanvas()
                        } label: {
                            Label(
                                removalPresentation.title,
                                systemImage: removalPresentation.systemImage
                            )
                        }
                        .help(removalPresentation.help)
                        .disabled(session.selectedNodeIDs.isEmpty)
                    }
                }
        }
        .navigationTitle(session.title)
        .task {
            await session.bootstrap()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, session.isReady else { return }
            Task { await session.flushPendingSave() }
        }
        .onDisappear {
            guard session.isReady else { return }
            Task { await session.flushPendingSave() }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image, .movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await session.importImages(from: urls, viewportSize: canvasViewportSize)
                }
            case .failure(let error):
                session.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $session.maskEditorPresentation) { presentation in
            if let asset = session.asset(for: presentation.sourceAssetID) {
                MaskEditorView(
                    sourceImageURL: session.assetURL(for: asset),
                    onCancel: { session.maskEditorPresentation = nil },
                    onCommit: { pngData, pixelSize in
                        Task {
                            await session.commitMaskEdit(
                                sourceAssetID: presentation.sourceAssetID,
                                generatorID: presentation.generatorID,
                                pngData: pngData,
                                pixelSize: pixelSize,
                                viewportSize: canvasViewportSize
                            )
                        }
                    }
                )
            } else {
                ContentUnavailableView(
                    "原图已不可用",
                    systemImage: "photo.badge.exclamationmark"
                )
                .frame(width: 420, height: 260)
            }
        }
        .alert(
            "无法完成操作",
            isPresented: Binding(
                get: { session.errorMessage != nil },
                set: { if !$0 { session.errorMessage = nil } }
            )
        ) {
            Button("好") {
                session.errorMessage = nil
            }
        } message: {
            Text(session.errorMessage ?? "发生未知错误")
        }
    }
}
