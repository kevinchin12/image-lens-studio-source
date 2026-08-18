import AppKit

/// A small AppKit boundary that normalizes the system pasteboard into media
/// the canvas already knows how to import. Video is intentionally accepted as
/// a file URL so large movie files are never copied through an in-memory Data
/// representation.
enum CanvasPasteboardMedia {
    case fileURLs([URL])
    case imageData(Data, mimeType: String, suggestedName: String)
}

@MainActor
enum CanvasPasteboardReader {
    private static let canvasNodeTokenType = NSPasteboard.PasteboardType(
        "com.imagelensstudio.canvas-node-token"
    )

    static func replaceContents(withCanvasNodeToken token: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(token, forType: canvasNodeTokenType)
    }

    static func containsCanvasNodeToken(_ token: String) -> Bool {
        NSPasteboard.general.string(forType: canvasNodeTokenType) == token
    }

    static func media(from pasteboard: NSPasteboard = .general) -> CanvasPasteboardMedia? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let fileURLs = (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) ?? []).compactMap { object -> URL? in
            guard let url = object as? NSURL else { return nil }
            return url as URL
        }

        if !fileURLs.isEmpty {
            return .fileURLs(fileURLs)
        }

        if let pngData = pasteboard.data(forType: .png) {
            return .imageData(
                pngData,
                mimeType: "image/png",
                suggestedName: "剪贴板图片.png"
            )
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return .imageData(
                pngData,
                mimeType: "image/png",
                suggestedName: "剪贴板图片.png"
            )
        }

        // Browsers and creative tools can expose JPEG, HEIC, or other image
        // representations without also publishing PNG/TIFF. NSImage performs
        // the pasteboard type negotiation, after which the repository receives
        // one normalized PNG payload.
        if let image = NSImage(pasteboard: pasteboard),
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return .imageData(
                pngData,
                mimeType: "image/png",
                suggestedName: "剪贴板图片.png"
            )
        }

        return nil
    }
}
