import Foundation

/// Best-effort tool details from a provider. Every field is optional —
/// the UI applies only non-empty values, and only to empty form fields.
struct ToolDetailsSuggestion: Codable, Equatable, Sendable {
    var name: String?
    var brand: String?
    /// Marketed model designation, e.g. "XDT17" or "OSC 18".
    var modelName: String?
    /// Manufacturer article/part number, e.g. "10041861".
    var modelNumber: String?
    /// All article numbers when the model ships in several kits or
    /// configurations (bare tool, set with batteries, …). The UI lets the
    /// user pick the variant they own; `modelNumber` stays the single
    /// answer when there is no ambiguity.
    var modelNumberOptions: [ModelNumberOption]?
    /// Taxonomy path guess like "Drill › SDS Plus" — mapped to an existing
    /// ToolType by the UI; ignored when nothing matches.
    var suggestedTypePath: String?
    /// "Corded" or "Battery" (matches PowerSource raw values).
    var powerSource: String?
    var batteryVoltage: Int?
    var batteryAmpHours: Double?
    var manufacturerLink: String?
    var howToLink: String?
    var notes: String?
}

/// One article/model number variant of a tool, e.g. Festool sells the
/// OSC 18 as 576589 (bare tool) and 576590 (set with battery and charger).
struct ModelNumberOption: Codable, Equatable, Sendable, Hashable {
    var number: String?
    /// What distinguishes this variant, e.g. "Bare tool" or
    /// "Set with battery, charger, and accessories".
    var detail: String?
    /// True when the provider is confident this is the variant the user
    /// means; at most one option should carry it.
    var isLikely: Bool?
}

struct LabeledLink: Codable, Equatable, Sendable, Hashable {
    var title: String?
    var url: String?
}

struct LinkSuggestions: Codable, Equatable, Sendable {
    var manufacturerLink: String?
    var howToLinks: [LabeledLink]?
}

struct CompanionSuggestion: Codable, Equatable, Sendable, Hashable {
    var name: String?
    var reason: String?
    /// Query for finding the tool in the user's inventory or a shop search.
    var searchQuery: String?
}

/// Value snapshot of a Tool handed to providers — they never touch
/// SwiftData objects.
struct ToolSnapshot: Codable, Equatable, Sendable {
    var name: String
    var brand: String
    var modelName: String
    var modelNumber: String
    var typePath: String?
    var powerSource: String?
    var batteryVoltage: Int?
    var batteryAmpHours: Double?
    var notes: String

    init(tool: Tool) {
        // displayName, not the legacy name field, so prompts always have a
        // meaningful title for the tool.
        name = tool.displayName
        brand = tool.brand
        modelName = tool.modelName
        modelNumber = tool.modelNumber
        typePath = tool.type?.path
        powerSource = tool.powerSource?.rawValue
        batteryVoltage = tool.batteryVoltage
        batteryAmpHours = tool.batteryAmpHours
        notes = tool.notes
    }

    init(name: String, brand: String = "", modelName: String = "",
         modelNumber: String = "", typePath: String? = nil,
         powerSource: String? = nil, batteryVoltage: Int? = nil,
         batteryAmpHours: Double? = nil, notes: String = "") {
        self.name = name
        self.brand = brand
        self.modelName = modelName
        self.modelNumber = modelNumber
        self.typePath = typePath
        self.powerSource = powerSource
        self.batteryVoltage = batteryVoltage
        self.batteryAmpHours = batteryAmpHours
        self.notes = notes
    }
}

/// Every case that originates from a specific provider names it, so the user
/// always knows which service failed and what they can do about it.
enum AIError: LocalizedError, Equatable {
    case unavailable(String)
    case missingAPIKey(AIProviderID)
    case unauthorized(AIProviderID)
    case offline
    case badResponse(AIProviderID, String)
    case rateLimited(AIProviderID, detail: String?)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            reason
        case .missingAPIKey(let provider):
            "\(provider.shortName) needs an API key. Add one in AI Settings, or select a different provider."
        case .unauthorized(let provider):
            "\(provider.shortName) rejected the API key (HTTP 401). Re-check the key in AI Settings."
        case .offline:
            "AI lookup needs a network connection. The Apple on-device model works offline."
        case .badResponse(let provider, let detail):
            "\(provider.shortName) returned an unexpected response: \(detail)"
        case .rateLimited(let provider, let detail):
            Self.rateLimitMessage(provider: provider, detail: detail)
        }
    }

    private static func rateLimitMessage(provider: AIProviderID, detail: String?) -> String {
        var parts = ["\(provider.shortName) turned the request away because of a rate or usage limit (HTTP 429)."]
        if let detail, !detail.isEmpty {
            parts.append("\(provider.shortName) says: \(detail)")
        }
        switch provider {
        case .claude:
            parts.append("Wait and retry, review your plan and limits at console.anthropic.com, or pick another provider in AI Settings.")
        case .gemini:
            parts.append("If this happens without recent use, the key's Google project may have no quota for this model or for search grounding — check aistudio.google.com, or pick another provider in AI Settings.")
        case .foundationModels:
            parts.append("Wait a moment and try again.")
        }
        return parts.joined(separator: " ")
    }

    /// Anthropic and Google both wrap failures as {"error": {"message": …}};
    /// surface that message so the user sees the provider's own explanation
    /// instead of a bare status code.
    static func apiErrorMessage(from data: Data) -> String? {
        struct Envelope: Decodable {
            struct Payload: Decodable { let message: String? }
            let error: Payload?
        }
        guard let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message,
              !message.isEmpty else { return nil }
        return String(message.prefix(300))
    }
}
