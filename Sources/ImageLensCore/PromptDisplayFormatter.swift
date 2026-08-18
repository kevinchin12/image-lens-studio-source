import Foundation

/// Presentation-only formatting for compiled prompts.
///
/// Compilation keeps semicolon separators for provider requests and stable
/// fingerprints. Canvas previews instead show each resolved module on its own
/// line so punctuation already present in a module is not doubled visually.
public enum PromptDisplayFormatter {
    public static func generatorNodeText(
        for snapshot: CompiledPromptSnapshot?
    ) -> String {
        guard let snapshot else { return "" }

        let overrideText = snapshot.override?.text
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !overrideText.isEmpty {
            return snapshot.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let moduleLines = snapshot.moduleInputs
            .map(\.resolvedContent)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !moduleLines.isEmpty {
            return moduleLines.joined(separator: "\n")
        }

        return snapshot.finalText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"(?<=[。！？.!?])\s*[;；]\s*"#,
                with: "\n",
                options: .regularExpression
            )
    }
}
