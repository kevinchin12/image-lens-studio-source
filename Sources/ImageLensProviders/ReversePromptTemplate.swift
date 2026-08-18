import Foundation

public struct ReversePromptTemplate: Equatable, Sendable {
    public let includeChinese: Bool

    public init(includeChinese: Bool) {
        self.includeChinese = includeChinese
    }

    public var text: String {
        [
            roleSection,
            moduleSection,
            evidenceSection,
            languageSection,
            contractSection
        ].joined(separator: "\n\n")
    }

    private var roleSection: String {
        """
        ROLE
        You are a visual reverse-analysis engine. Convert only the visible and cautiously inferable properties of the supplied image into reusable prompt modules. The output is structured data for a deterministic compiler, not marketing copy and not a single monolithic prompt.
        """
    }

    private var moduleSection: String {
        """
        REQUIRED MODULES
        Return exactly these eight modules, even when a module must be empty:
        1. subject — visible people, objects, pose, action, shape, and distinguishing non-identity attributes.
        2. style — visible medium, genre, treatment, palette character, and overall visual language.
        3. lighting — visible direction, hardness, contrast, color, falloff, and shadow behavior.
        4. camera — visible framing, viewpoint, shot scale, perspective, and depth-of-field appearance; lens or aperture claims are inferred unless metadata is supplied.
        5. environment — visible setting, background, spatial relationship, weather, and time cues.
        6. material — visible surface, texture, reflectance, transparency, wear, and micro-detail; exact material identity is inferred unless unambiguous.
        7. composition — visible placement, balance, symmetry, layering, negative space, leading lines, and crop.
        8. rendering — visible finishing, grain, sharpness, color grade, and 2D/3D/photographic appearance; exact renderer, software, or device is inferred unless metadata is supplied.

        Write each promptEnglish value as a concise, reusable fragment. Do not add empty praise such as beautiful, amazing, stunning, masterpiece, best quality, or high quality. If a category cannot be supported, return an empty prompt and an empty evidence array rather than inventing it.
        """
    }

    private var evidenceSection: String {
        """
        OBSERVABLE / INFERRED BOUNDARY
        Every non-empty module requires one or more evidence entries.
        - observable: directly grounded in visible pixels, including count, color, geometry, placement, texture appearance, shadow direction, framing, and clearly depicted action.
        - inferred: a cautious interpretation that is not directly proven by pixels, including exact focal length, aperture, named material, render engine, camera/device, production technique, time period, mood, intent, or real-world identity.

        Keep each evidence statement atomic. Label inferred claims as inferred and phrase them without false certainty. A prompt may combine both kinds, but its evidence array must preserve the boundary claim by claim.

        Never identify a real person, private individual, brand, trademark, artist, copyrighted character, client, location, camera model, or render engine unless that fact is explicitly supplied as trusted metadata. Never claim hidden scene content or personal intent. Use generic visual descriptions instead.
        """
    }

    private var languageSection: String {
        if includeChinese {
            """
            LANGUAGE
            promptEnglish and all evidence statements must be English. For every non-empty promptEnglish value, promptChinese must be a faithful Chinese semantic translation with no added facts. Return 6–12 concise English keywords and the same concepts in Chinese, with matching array lengths and order.
            """
        } else {
            """
            LANGUAGE
            promptEnglish and all evidence statements must be English. Set every promptChinese value to an empty string and keywords.chinese to an empty array. Return 6–12 concise English keywords.
            """
        }
    }

    private var contractSection: String {
        """
        STRICT JSON CONTRACT
        Return one valid JSON object only. Do not return Markdown, code fences, comments, explanations, extra keys, null, or trailing commas. Use schemaVersion exactly "\(ReversePromptSchema.version)". title must be a concise English title. Each evidence kind must be exactly "observable" or "inferred".

        \(Self.jsonShape)
        """
    }

    public static let jsonShape = #"{"schemaVersion":"image-lens.reverse-prompt.v1","title":"","modules":{"subject":{"promptEnglish":"","promptChinese":"","evidence":[{"kind":"observable","statement":""}]},"style":{"promptEnglish":"","promptChinese":"","evidence":[]},"lighting":{"promptEnglish":"","promptChinese":"","evidence":[]},"camera":{"promptEnglish":"","promptChinese":"","evidence":[]},"environment":{"promptEnglish":"","promptChinese":"","evidence":[]},"material":{"promptEnglish":"","promptChinese":"","evidence":[]},"composition":{"promptEnglish":"","promptChinese":"","evidence":[]},"rendering":{"promptEnglish":"","promptChinese":"","evidence":[]}},"keywords":{"english":[],"chinese":[]}}"#
}
