import Foundation
import ImageLensCore

public enum ReversePromptOutputLanguage: Sendable {
    case english
    case chinese
}

public extension ReversePromptResponseDTO {
    /// Converts validated provider output into the canonical reusable modules.
    ///
    /// Empty categories stay represented in the provider DTO but are omitted from
    /// Core because an empty value is a Recipe slot, not a reusable PromptModule.
    /// If any supporting claim is inferred, the Core module is conservatively
    /// labelled inferred rather than overstating the whole fragment as observable.
    func makePromptModules(
        sourceAssetID: AssetID? = nil,
        sourceAnalysisSnapshotID: AnalysisSnapshotID? = nil,
        language: ReversePromptOutputLanguage = .english,
        timestamp: Date = .now
    ) -> [PromptModule] {
        orderedModules.compactMap { kind, module in
            let content: String
            switch language {
            case .english:
                content = module.promptEnglish
            case .chinese:
                content = module.promptChinese
            }

            let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedContent.isEmpty else { return nil }

            let evidence: PromptEvidence = module.evidence.contains(where: { $0.kind == .inferred })
                ? .inferred
                : .observable
            let evidenceClaims = module.evidence.map {
                PromptEvidenceClaim(
                    kind: $0.kind.promptEvidence,
                    statement: $0.statement.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            return PromptModule(
                category: kind.promptModuleCategory,
                content: normalizedContent,
                sourceAssetID: sourceAssetID,
                sourceAnalysisSnapshotID: sourceAnalysisSnapshotID,
                evidence: evidence,
                evidenceClaims: evidenceClaims,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        }
    }
}

private extension ReversePromptEvidenceKind {
    var promptEvidence: PromptEvidence {
        switch self {
        case .observable: .observable
        case .inferred: .inferred
        }
    }
}

private extension ReversePromptModuleKind {
    var promptModuleCategory: PromptModuleCategory {
        switch self {
        case .subject: .subject
        case .style: .style
        case .lighting: .lighting
        case .camera: .camera
        case .environment: .environment
        case .material: .material
        case .composition: .composition
        case .rendering: .rendering
        }
    }
}
