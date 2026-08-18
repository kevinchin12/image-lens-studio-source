import AppKit
import ImageLensCore
import UniformTypeIdentifiers

@MainActor
enum AssetExportCoordinator {
    static func export(_ assetID: AssetID, from session: WorkspaceSession) async {
        guard let asset = session.asset(for: assetID) else {
            session.errorMessage = "要导出的生成结果已不在项目中"
            return
        }

        do {
            let sourceURL = try await session.resolvedAssetURL(for: asset)
            let fileExtension = sourceURL.pathExtension.lowercased()
            let contentType = UTType(filenameExtension: fileExtension)
                ?? UTType(mimeType: asset.mimeType)
                ?? .data

            let panel = NSSavePanel()
            panel.title = "导出生成结果"
            panel.prompt = "导出"
            panel.allowedContentTypes = [contentType]
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.nameFieldStringValue = suggestedFileName(
                displayName: asset.displayName,
                fileExtension: fileExtension
            )
            guard panel.runModal() == .OK, var destinationURL = panel.url else { return }
            if !fileExtension.isEmpty,
               destinationURL.pathExtension.lowercased() != fileExtension {
                destinationURL.appendPathExtension(fileExtension)
            }
            await session.exportAsset(assetID, to: destinationURL)
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }

    static func suggestedFileName(displayName: String, fileExtension: String) -> String {
        let stem = URL(fileURLWithPath: displayName)
            .deletingPathExtension()
            .lastPathComponent
        let invalid = CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: #"/:\"#))
        let cleaned = stem.unicodeScalars.map { scalar in
            invalid.contains(scalar) ? "-" : String(scalar)
        }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeStem = cleaned.isEmpty || cleaned == "." || cleaned == ".."
            ? "生成结果"
            : cleaned
        return fileExtension.isEmpty ? safeStem : "\(safeStem).\(fileExtension)"
    }
}
