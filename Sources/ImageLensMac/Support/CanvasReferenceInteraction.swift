import ImageLensCore
import SwiftUI

struct CanvasReferenceNodeDropTarget: Hashable {
    let generatorID: GeneratorID
    let acceptedMediaKinds: Set<AssetMediaKind>

    init(
        generatorID: GeneratorID,
        acceptedMediaKinds: Set<AssetMediaKind> = [.image]
    ) {
        self.generatorID = generatorID
        self.acceptedMediaKinds = acceptedMediaKinds
    }

    func accepts(_ mediaKind: AssetMediaKind) -> Bool {
        acceptedMediaKinds.contains(mediaKind)
    }
}

struct CanvasReferenceNodeDropTargetFrame: Equatable {
    let target: CanvasReferenceNodeDropTarget
    let frame: CGRect
}

struct CanvasReferenceNodeDropTargetPreferenceKey: PreferenceKey {
    static let defaultValue: [CanvasReferenceNodeDropTargetFrame] = []

    static func reduce(
        value: inout [CanvasReferenceNodeDropTargetFrame],
        nextValue: () -> [CanvasReferenceNodeDropTargetFrame]
    ) {
        value.append(contentsOf: nextValue())
    }
}

struct CanvasPromptNodeDropTarget: Hashable {
    let generatorID: GeneratorID
}

struct CanvasPromptNodeDropTargetFrame: Equatable {
    let target: CanvasPromptNodeDropTarget
    let frame: CGRect
}

struct CanvasPromptNodeDropTargetPreferenceKey: PreferenceKey {
    static let defaultValue: [CanvasPromptNodeDropTargetFrame] = []

    static func reduce(
        value: inout [CanvasPromptNodeDropTargetFrame],
        nextValue: () -> [CanvasPromptNodeDropTargetFrame]
    ) {
        value.append(contentsOf: nextValue())
    }
}

extension GeneratorAssetRole {
    var canvasReferenceTitle: String {
        switch self {
        case .general: "整体"
        case .identity: "主体"
        case .environment: "场景"
        case .style: "风格"
        case .composition: "构图"
        case .palette: "色彩"
        case .structure: "结构"
        }
    }
}
