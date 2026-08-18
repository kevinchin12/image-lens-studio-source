import Foundation

public enum WorkspaceDisplayNameKind: String, CaseIterable, Sendable {
    case recipe = "提示词组合"
    case generator = "生图"
    case generationGroup = "生成结果"
}

/// Generates predictable user-facing names without coupling identity to
/// collection counts. Default names use monotonically increasing ordinals
/// within the names currently present in a workspace; copied custom names use
/// a compact "副本" suffix instead of silently duplicating the source name.
public enum WorkspaceDisplayNamePolicy {
    public static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func nextDefaultName(
        for kind: WorkspaceDisplayNameKind,
        existingNames: some Sequence<String>
    ) -> String {
        let existing = existingNames.map(normalized)
        let highestOrdinal = existing.compactMap {
            defaultOrdinal(in: $0, for: kind)
        }.max() ?? 0
        return "\(kind.rawValue) \(highestOrdinal + 1)"
    }

    public static func copiedName(
        from sourceName: String,
        for kind: WorkspaceDisplayNameKind,
        existingNames: some Sequence<String>
    ) -> String {
        let source = normalized(sourceName)
        let existing = Set(existingNames.map(normalized))

        guard !source.isEmpty,
              defaultOrdinal(in: source, for: kind) == nil else {
            return nextDefaultName(for: kind, existingNames: existing)
        }

        let base = copyBaseName(from: source)
        guard existing.contains(base) else { return base }

        let highestCopyOrdinal = existing.compactMap {
            copyOrdinal(in: $0, base: base)
        }.max() ?? 1
        return "\(base) \(highestCopyOrdinal + 1)"
    }

    public static func isDefaultName(
        _ name: String,
        for kind: WorkspaceDisplayNameKind
    ) -> Bool {
        defaultOrdinal(in: normalized(name), for: kind) != nil
    }

    private static func defaultOrdinal(
        in name: String,
        for kind: WorkspaceDisplayNameKind
    ) -> Int? {
        let prefix = "\(kind.rawValue) "
        guard name.hasPrefix(prefix),
              let ordinal = Int(name.dropFirst(prefix.count)),
              ordinal > 0,
              name == "\(kind.rawValue) \(ordinal)" else {
            return nil
        }
        return ordinal
    }

    private static func copyBaseName(from name: String) -> String {
        let components = name.split(separator: " ", omittingEmptySubsequences: true)
        if components.last == "副本" {
            return name
        }
        if components.count >= 3,
           Int(components.last ?? "") != nil,
           components[components.index(components.endIndex, offsetBy: -2)] == "副本" {
            return components.dropLast().joined(separator: " ")
        }
        return "\(name) 副本"
    }

    private static func copyOrdinal(in candidate: String, base: String) -> Int? {
        if candidate == base { return 1 }
        let prefix = "\(base) "
        guard candidate.hasPrefix(prefix),
              let ordinal = Int(candidate.dropFirst(prefix.count)),
              ordinal >= 2,
              candidate == "\(base) \(ordinal)" else {
            return nil
        }
        return ordinal
    }
}
