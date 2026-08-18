import Foundation

/// Plain canvas text that is independent from prompt compilation.
/// Prompt instructions remain `PromptModule` entities; notes never acquire
/// recipe bindings merely because they are placed beside an action node.
public enum TextBlockKind: String, Codable, CaseIterable, Sendable {
    case note
}

public struct TextBlock: Codable, Equatable, Identifiable, Sendable {
    public var id: TextBlockID
    public var kind: TextBlockKind
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: TextBlockID = TextBlockID(),
        kind: TextBlockKind = .note,
        text: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
