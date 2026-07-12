import Foundation

enum AIProviderID: String, CaseIterable, Identifiable, Codable, Sendable {
    case foundationModels
    case claude
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .foundationModels: "Apple Intelligence (On-Device)"
        case .claude: "Claude (Anthropic)"
        case .gemini: "Gemini (Google)"
        }
    }
}

/// A pluggable AI backend. All generation methods return the shared DTOs;
/// AIService performs availability / network / key checks before calling.
protocol AIProvider {
    var id: AIProviderID { get }
    var requiresAPIKey: Bool { get }
    var requiresNetwork: Bool { get }
    /// OS / model availability only — network and key checks live in AIService.
    var isAvailable: Bool { get }
    var unavailabilityReason: String? { get }

    func lookupToolDetails(brand: String, model: String) async throws -> ToolDetailsSuggestion
    func lookupToolDetails(barcode: String) async throws -> ToolDetailsSuggestion
    func extractDetails(fromImage jpegData: Data) async throws -> ToolDetailsSuggestion
    func suggestLinks(brand: String, model: String) async throws -> LinkSuggestions
    func suggestCompanions(for tool: ToolSnapshot) async throws -> [CompanionSuggestion]
}

extension AIProvider {
    var displayName: String { id.displayName }
}
