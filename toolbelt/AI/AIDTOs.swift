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

enum AIError: LocalizedError, Equatable {
    case unavailable(String)
    case missingAPIKey
    case offline
    case badResponse(String)
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            reason
        case .missingAPIKey:
            "Add an API key for the selected AI provider in Settings."
        case .offline:
            "AI lookup needs a network connection. The Apple on-device model works offline."
        case .badResponse(let detail):
            "The AI provider returned an unexpected response: \(detail)"
        case .rateLimited:
            "The AI provider is rate-limiting requests. Try again shortly."
        }
    }
}
