import Foundation
import ImageLensCore
import UniformTypeIdentifiers

struct CanvasImageDropRejection: Equatable, Sendable {
    let sourceURL: URL?
    let reason: String

    var message: String {
        guard let sourceURL else { return reason }
        return "\(sourceURL.lastPathComponent)：\(reason)"
    }
}

struct CanvasImageDropResult: Equatable, Sendable {
    enum Disposition: String, Equatable, Sendable {
        case accepted
        case rejected
    }

    let disposition: Disposition
    let acceptedSourceCount: Int
    let canvasNodeIDs: [CanvasNodeID]
    let rejections: [CanvasImageDropRejection]

    var isAccepted: Bool { disposition == .accepted }

    init(
        acceptedSourceCount: Int,
        canvasNodeIDs: [CanvasNodeID] = [],
        rejections: [CanvasImageDropRejection] = []
    ) {
        self.disposition = acceptedSourceCount > 0 ? .accepted : .rejected
        self.acceptedSourceCount = acceptedSourceCount
        self.canvasNodeIDs = canvasNodeIDs
        self.rejections = rejections
    }
}

struct CanvasImageDropProviderLoadResult: Equatable, Sendable {
    let fileURLs: [URL]
    let rejections: [CanvasImageDropRejection]
}

/// Shared Finder-drop boundary for either `dropDestination(for: URL.self)` or
/// the older `onDrop(of:)` provider API. The actual managed import stays in
/// `WorkspaceSession` and `WorkspacePackageRepository`.
@MainActor
enum CanvasImageFileDrop {
    private static let supportedVideoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    static var acceptedContentTypes: [UTType] { [.fileURL] }
    static var acceptedTypeIdentifiers: [String] { acceptedContentTypes.map(\.identifier) }

    static func canAccept(_ providers: [NSItemProvider]) -> Bool {
        providers.contains { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
    }

    static func canAccept(_ sourceURLs: [URL]) -> Bool {
        !validate(sourceURLs).accepted.isEmpty
    }

    static func validate(_ sourceURLs: [URL]) -> (
        accepted: [URL],
        rejected: [CanvasImageDropRejection]
    ) {
        var accepted: [URL] = []
        var rejected: [CanvasImageDropRejection] = []

        for sourceURL in sourceURLs {
            guard sourceURL.isFileURL else {
                rejected.append(
                    CanvasImageDropRejection(sourceURL: sourceURL, reason: "只支持本地图片或视频文件")
                )
                continue
            }

            let fileExtension = sourceURL.pathExtension.lowercased()
            guard !fileExtension.isEmpty,
                  let contentType = UTType(filenameExtension: fileExtension),
                  contentType.conforms(to: .image)
                    || (contentType.conforms(to: .movie)
                        && supportedVideoExtensions.contains(fileExtension)) else {
                rejected.append(
                    CanvasImageDropRejection(sourceURL: sourceURL, reason: "不是支持的图片或视频文件")
                )
                continue
            }

            accepted.append(sourceURL.standardizedFileURL)
        }

        if sourceURLs.isEmpty {
            rejected.append(CanvasImageDropRejection(sourceURL: nil, reason: "没有收到可导入的文件"))
        }
        return (accepted, rejected)
    }

    /// Resolves Finder `public.file-url` providers for an `onDrop` integration.
    /// Prefer `dropDestination(for: URL.self)` when possible because SwiftUI
    /// performs this transfer decoding directly.
    static func loadFileURLs(from providers: [NSItemProvider]) async -> CanvasImageDropProviderLoadResult {
        var fileURLs: [URL] = []
        var rejections: [CanvasImageDropRejection] = []

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            do {
                fileURLs.append(try await loadFileURL(from: provider))
            } catch {
                rejections.append(
                    CanvasImageDropRejection(sourceURL: nil, reason: error.localizedDescription)
                )
            }
        }

        if fileURLs.isEmpty, rejections.isEmpty {
            rejections.append(CanvasImageDropRejection(sourceURL: nil, reason: "拖入内容不包含图片或视频文件 URL"))
        }
        return CanvasImageDropProviderLoadResult(fileURLs: fileURLs, rejections: rejections)
    }

    private static func loadFileURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let url = item as? NSURL {
                    continuation.resume(returning: url as URL)
                    return
                }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }
                if let value = item as? String {
                    let url = URL(string: value) ?? URL(fileURLWithPath: value)
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(throwing: CanvasImageDropProviderError.unreadableFileURL)
            }
        }
    }
}

private enum CanvasImageDropProviderError: LocalizedError {
    case unreadableFileURL

    var errorDescription: String? {
        switch self {
        case .unreadableFileURL: "无法读取拖入项目的文件 URL"
        }
    }
}
