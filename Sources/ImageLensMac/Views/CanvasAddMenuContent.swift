import ImageLensCanvas
import SwiftUI

/// Shared commands for every canvas "Add" entry point.
struct CanvasAddMenuContent: View {
    let session: WorkspaceSession
    let viewportSize: ViewSize
    let onImportMedia: () -> Void

    var body: some View {
        Button("导入图片或视频…", systemImage: "photo.on.rectangle.angled") {
            onImportMedia()
        }
        .keyboardShortcut("i", modifiers: [.command, .shift])
        .disabled(session.isImporting)

        Divider()

        Button("创作指令", systemImage: "text.badge.plus") {
            Task { await session.createInstructionModule(viewportSize: viewportSize) }
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])

        Button("备注", systemImage: "note.text") {
            Task { await session.createNoteModule(viewportSize: viewportSize) }
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])

        Divider()

        Button("图片生成", systemImage: "sparkles") {
            Task { await session.createGenerator(mediaKind: .image, viewportSize: viewportSize) }
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])

        Button("视频生成", systemImage: "film.stack") {
            Task { await session.createGenerator(mediaKind: .video, viewportSize: viewportSize) }
        }
    }
}
