import AppKit
import AVFoundation
import ImageLensCore
import SwiftUI

struct AssetThumbnailView: View {
    let session: WorkspaceSession
    let asset: Asset
    let size: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.quaternary)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if asset.isVideo {
                Image(systemName: "film")
                    .font(.system(size: max(12, size * 0.34), weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: asset.kind == .generated ? "sparkles.rectangle.stack" : "photo")
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        }
        .task(id: asset.relativePath) {
            if asset.isVideo {
                guard let url = try? await session.resolvedAssetURL(for: asset) else {
                    image = nil
                    return
                }
                image = await Task.detached(priority: .utility) {
                    let source = AVURLAsset(url: url)
                    let generator = AVAssetImageGenerator(asset: source)
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: 320, height: 320)
                    guard let frame = try? await generator.image(
                        at: CMTime(seconds: 0.1, preferredTimescale: 600)
                    ).image else { return nil }
                    return NSImage(cgImage: frame, size: .zero)
                }.value
            } else {
                let url = session.assetURL(for: asset)
                let data = await Task.detached(priority: .utility) {
                    try? Data(contentsOf: url, options: [.mappedIfSafe])
                }.value
                image = data.flatMap(NSImage.init(data:))
            }
        }
        .accessibilityLabel(asset.isVideo ? "\(asset.displayName) 视频" : "\(asset.displayName) 缩略图")
    }
}
