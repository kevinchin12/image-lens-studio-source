import Foundation

/// The fixed visual vocabulary used by the first reverse-prompt contract.
public enum ReversePromptModuleKind: String, CaseIterable, Codable, Sendable {
    case subject
    case style
    case lighting
    case camera
    case environment
    case material
    case composition
    case rendering
}

/// Describes whether a supporting statement comes directly from visible pixels
/// or is a qualified interpretation made by the model.
public enum ReversePromptEvidenceKind: String, Codable, Sendable {
    case observable
    case inferred
}

public struct ReversePromptEvidenceDTO: Codable, Equatable, Sendable {
    public var kind: ReversePromptEvidenceKind
    public var statement: String

    public init(kind: ReversePromptEvidenceKind, statement: String) {
        self.kind = kind
        self.statement = statement
    }
}

public struct ReversePromptModuleDTO: Codable, Equatable, Sendable {
    public var promptEnglish: String
    public var promptChinese: String
    public var evidence: [ReversePromptEvidenceDTO]

    public init(
        promptEnglish: String,
        promptChinese: String = "",
        evidence: [ReversePromptEvidenceDTO]
    ) {
        self.promptEnglish = promptEnglish
        self.promptChinese = promptChinese
        self.evidence = evidence
    }
}

/// Named properties deliberately mirror the JSON contract. This makes a missing
/// visual category a decoding failure instead of silently accepting a partial array.
public struct ReversePromptModulesDTO: Codable, Equatable, Sendable {
    public var subject: ReversePromptModuleDTO
    public var style: ReversePromptModuleDTO
    public var lighting: ReversePromptModuleDTO
    public var camera: ReversePromptModuleDTO
    public var environment: ReversePromptModuleDTO
    public var material: ReversePromptModuleDTO
    public var composition: ReversePromptModuleDTO
    public var rendering: ReversePromptModuleDTO

    public init(
        subject: ReversePromptModuleDTO,
        style: ReversePromptModuleDTO,
        lighting: ReversePromptModuleDTO,
        camera: ReversePromptModuleDTO,
        environment: ReversePromptModuleDTO,
        material: ReversePromptModuleDTO,
        composition: ReversePromptModuleDTO,
        rendering: ReversePromptModuleDTO
    ) {
        self.subject = subject
        self.style = style
        self.lighting = lighting
        self.camera = camera
        self.environment = environment
        self.material = material
        self.composition = composition
        self.rendering = rendering
    }

    public subscript(kind: ReversePromptModuleKind) -> ReversePromptModuleDTO {
        switch kind {
        case .subject: subject
        case .style: style
        case .lighting: lighting
        case .camera: camera
        case .environment: environment
        case .material: material
        case .composition: composition
        case .rendering: rendering
        }
    }
}

public struct ReversePromptKeywordsDTO: Codable, Equatable, Sendable {
    public var english: [String]
    public var chinese: [String]

    public init(english: [String], chinese: [String] = []) {
        self.english = english
        self.chinese = chinese
    }
}

public struct ReversePromptResponseDTO: Codable, Equatable, Sendable {
    public var schemaVersion: String
    public var title: String
    public var modules: ReversePromptModulesDTO
    public var keywords: ReversePromptKeywordsDTO

    public init(
        schemaVersion: String = ReversePromptSchema.version,
        title: String,
        modules: ReversePromptModulesDTO,
        keywords: ReversePromptKeywordsDTO
    ) {
        self.schemaVersion = schemaVersion
        self.title = title
        self.modules = modules
        self.keywords = keywords
    }

    /// Returns every module in compiler order, independent of JSON object ordering.
    public var orderedModules: [(kind: ReversePromptModuleKind, module: ReversePromptModuleDTO)] {
        ReversePromptModuleKind.allCases.map { ($0, modules[$0]) }
    }
}

public enum ReversePromptSchemaError: Error, Equatable, LocalizedError, Sendable {
    case invalidJSONObject
    case invalidObject(path: String)
    case unexpectedKeys(path: String, expected: [String], actual: [String])
    case invalidVersion(String)
    case invalidValue(path: String, reason: String)
    case decodingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidJSONObject:
            "The response is not a valid JSON object."
        case .invalidObject(let path):
            "Expected an object at \(path)."
        case .unexpectedKeys(let path, let expected, let actual):
            "Unexpected keys at \(path). Expected \(expected.sorted()), got \(actual.sorted())."
        case .invalidVersion(let version):
            "Unsupported reverse-prompt schema version: \(version)."
        case .invalidValue(let path, let reason):
            "Invalid value at \(path): \(reason)"
        case .decodingFailed(let message):
            "Could not decode reverse-prompt response: \(message)"
        }
    }
}

/// Validates the complete wire contract before decoding. `JSONDecoder` alone
/// ignores unknown keys, which is too permissive for a model-generated response.
public enum ReversePromptSchema {
    public static let version = "image-lens.reverse-prompt.v1"

    public static func decode(
        _ data: Data,
        includeChinese: Bool
    ) throws -> ReversePromptResponseDTO {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ReversePromptSchemaError.invalidJSONObject
        }

        guard let root = object as? [String: Any] else {
            throw ReversePromptSchemaError.invalidJSONObject
        }

        try requireExactKeys(
            in: root,
            path: "$",
            expected: ["schemaVersion", "title", "modules", "keywords"]
        )

        guard let schemaVersion = root["schemaVersion"] as? String else {
            throw ReversePromptSchemaError.invalidValue(path: "$.schemaVersion", reason: "expected a string")
        }
        guard schemaVersion == version else {
            throw ReversePromptSchemaError.invalidVersion(schemaVersion)
        }

        guard let modules = root["modules"] as? [String: Any] else {
            throw ReversePromptSchemaError.invalidObject(path: "$.modules")
        }
        try requireExactKeys(
            in: modules,
            path: "$.modules",
            expected: ReversePromptModuleKind.allCases.map(\.rawValue)
        )

        for kind in ReversePromptModuleKind.allCases {
            let path = "$.modules.\(kind.rawValue)"
            guard let module = modules[kind.rawValue] as? [String: Any] else {
                throw ReversePromptSchemaError.invalidObject(path: path)
            }
            try requireExactKeys(
                in: module,
                path: path,
                expected: ["promptEnglish", "promptChinese", "evidence"]
            )

            guard module["promptEnglish"] is String else {
                throw ReversePromptSchemaError.invalidValue(path: "\(path).promptEnglish", reason: "expected a string")
            }
            guard module["promptChinese"] is String else {
                throw ReversePromptSchemaError.invalidValue(path: "\(path).promptChinese", reason: "expected a string")
            }
            guard let evidence = module["evidence"] as? [[String: Any]] else {
                throw ReversePromptSchemaError.invalidValue(path: "\(path).evidence", reason: "expected an array of objects")
            }
            for (index, item) in evidence.enumerated() {
                let evidencePath = "\(path).evidence[\(index)]"
                try requireExactKeys(
                    in: item,
                    path: evidencePath,
                    expected: ["kind", "statement"]
                )
            }
        }

        guard let keywords = root["keywords"] as? [String: Any] else {
            throw ReversePromptSchemaError.invalidObject(path: "$.keywords")
        }
        try requireExactKeys(
            in: keywords,
            path: "$.keywords",
            expected: ["english", "chinese"]
        )

        let response: ReversePromptResponseDTO
        do {
            response = try JSONDecoder().decode(ReversePromptResponseDTO.self, from: data)
        } catch {
            throw ReversePromptSchemaError.decodingFailed(String(describing: error))
        }

        try validate(response, includeChinese: includeChinese)
        return response
    }

    public static func validate(
        _ response: ReversePromptResponseDTO,
        includeChinese: Bool
    ) throws {
        guard response.schemaVersion == version else {
            throw ReversePromptSchemaError.invalidVersion(response.schemaVersion)
        }
        guard !response.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReversePromptSchemaError.invalidValue(path: "$.title", reason: "must not be empty")
        }

        for (kind, module) in response.orderedModules {
            let path = "$.modules.\(kind.rawValue)"
            let english = module.promptEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
            let chinese = module.promptChinese.trimmingCharacters(in: .whitespacesAndNewlines)

            if english.isEmpty, !module.evidence.isEmpty {
                throw ReversePromptSchemaError.invalidValue(
                    path: path,
                    reason: "an empty prompt must have no evidence"
                )
            }
            if english.isEmpty, !chinese.isEmpty {
                throw ReversePromptSchemaError.invalidValue(
                    path: "\(path).promptChinese",
                    reason: "must be empty when the canonical English prompt is empty"
                )
            }
            if !english.isEmpty, module.evidence.isEmpty {
                throw ReversePromptSchemaError.invalidValue(
                    path: "\(path).evidence",
                    reason: "a non-empty prompt requires supporting evidence"
                )
            }
            for (index, evidence) in module.evidence.enumerated() {
                guard !evidence.statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ReversePromptSchemaError.invalidValue(
                        path: "\(path).evidence[\(index)].statement",
                        reason: "must not be empty"
                    )
                }
            }

            if includeChinese, !english.isEmpty, chinese.isEmpty {
                throw ReversePromptSchemaError.invalidValue(
                    path: "\(path).promptChinese",
                    reason: "must translate each non-empty English module when Chinese output is enabled"
                )
            }
            if !includeChinese, !chinese.isEmpty {
                throw ReversePromptSchemaError.invalidValue(
                    path: "\(path).promptChinese",
                    reason: "must be empty when Chinese output is disabled"
                )
            }
        }

        guard (6...12).contains(response.keywords.english.count),
              response.keywords.english.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ReversePromptSchemaError.invalidValue(
                path: "$.keywords.english",
                reason: "must contain 6 to 12 non-empty keywords"
            )
        }

        if includeChinese {
            guard response.keywords.chinese.count == response.keywords.english.count,
                  response.keywords.chinese.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw ReversePromptSchemaError.invalidValue(
                    path: "$.keywords.chinese",
                    reason: "must contain one non-empty translation for each English keyword"
                )
            }
        }

        if !includeChinese, !response.keywords.chinese.isEmpty {
            throw ReversePromptSchemaError.invalidValue(
                path: "$.keywords.chinese",
                reason: "must be empty when Chinese output is disabled"
            )
        }
    }

    private static func requireExactKeys(
        in object: [String: Any],
        path: String,
        expected: [String]
    ) throws {
        let actualSet = Set(object.keys)
        let expectedSet = Set(expected)
        guard actualSet == expectedSet else {
            throw ReversePromptSchemaError.unexpectedKeys(
                path: path,
                expected: expected,
                actual: Array(object.keys)
            )
        }
    }
}
