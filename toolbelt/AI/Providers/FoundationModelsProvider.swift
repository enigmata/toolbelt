import Foundation
import FoundationModels

/// Apple's on-device model (iOS 26 FoundationModels). Free, private, works
/// offline. Text-only: photo extraction is delegated to a cloud provider.
struct FoundationModelsProvider: AIProvider {
    let id = AIProviderID.foundationModels
    let requiresAPIKey = false
    let requiresNetwork = false

    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    var unavailabilityReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Enable Apple Intelligence in Settings to use the on-device model."
        case .unavailable(.modelNotReady):
            return "The on-device model is still downloading. Try again later."
        case .unavailable:
            return "The on-device model is unavailable."
        }
    }

    private static let instructions = """
        You help catalog a personal inventory of power tools and hand tools. \
        Answer only from well-established product knowledge; leave any field \
        you are not confident about empty rather than guessing.
        """

    // MARK: Generable mirrors (FoundationModels guided generation can't
    // consume the shared Codable DTOs directly).

    @Generable
    struct ToolDetailsGen {
        @Guide(description: "Product name, e.g. \"Cordless Hammer Drill\"")
        var name: String?
        @Guide(description: "Manufacturer brand, e.g. \"Makita\"")
        var brand: String?
        @Guide(description: "Marketed model designation, e.g. \"XDT17\" or \"OSC 18\"")
        var modelName: String?
        @Guide(description: "Manufacturer article/part number, e.g. \"10041861\" — not the model name")
        var modelNumber: String?
        @Guide(description: "Taxonomy path like \"Drill › SDS Plus\" or \"Chisel › Wood\"")
        var suggestedTypePath: String?
        @Guide(description: "Exactly \"Corded\" or \"Battery\" for power tools; empty for hand tools")
        var powerSource: String?
        @Guide(description: "Battery voltage in volts, e.g. 18")
        var batteryVoltage: Int?
        @Guide(description: "Battery capacity in amp-hours, e.g. 4.0")
        var batteryAmpHours: Double?
        @Guide(description: "Official manufacturer product page URL")
        var manufacturerLink: String?
        @Guide(description: "A how-to or tutorial video URL or search page")
        var howToLink: String?
        @Guide(description: "One-sentence tip about the tool")
        var notes: String?

        var dto: ToolDetailsSuggestion {
            ToolDetailsSuggestion(
                name: name, brand: brand, modelName: modelName, modelNumber: modelNumber,
                suggestedTypePath: suggestedTypePath, powerSource: powerSource,
                batteryVoltage: batteryVoltage, batteryAmpHours: batteryAmpHours,
                manufacturerLink: manufacturerLink, howToLink: howToLink, notes: notes
            )
        }
    }

    @Generable
    struct LinkSuggestionsGen {
        @Guide(description: "Official manufacturer product or spec page URL")
        var manufacturerLink: String?
        @Guide(description: "Up to 3 how-to / tutorial titles with URLs")
        var howToLinks: [LabeledLinkGen]?
    }

    @Generable
    struct LabeledLinkGen {
        var title: String?
        var url: String?
    }

    @Generable
    struct CompanionGen {
        @Guide(description: "Companion tool or accessory name")
        var name: String?
        @Guide(description: "Why it pairs well with the tool")
        var reason: String?
        @Guide(description: "Short search phrase for finding it")
        var searchQuery: String?
    }

    @Generable
    struct CompanionsGen {
        @Guide(description: "Up to 5 companion tools", .maximumCount(5))
        var companions: [CompanionGen]
    }

    // MARK: AIProvider

    func lookupToolDetails(brand: String, model: String) async throws -> ToolDetailsSuggestion {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: "Identify this tool and fill in its details. Brand: \(brand). Model name: \(model).",
            generating: ToolDetailsGen.self
        )
        return response.content.dto
    }

    func lookupToolDetails(barcode: String) async throws -> ToolDetailsSuggestion {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: """
                A tool product barcode was scanned with payload: \(barcode). \
                If the payload encodes recognizable product info, fill in the \
                details; otherwise leave fields empty.
                """,
            generating: ToolDetailsGen.self
        )
        return response.content.dto
    }

    func extractDetails(fromImage jpegData: Data) async throws -> ToolDetailsSuggestion {
        throw AIError.unavailable(
            "The on-device model is text-only. Use Claude or Gemini for photo extraction."
        )
    }

    func suggestLinks(brand: String, model: String) async throws -> LinkSuggestions {
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: "Suggest official documentation links for the tool \(brand) \(model).",
            generating: LinkSuggestionsGen.self
        )
        let generated = response.content
        return LinkSuggestions(
            manufacturerLink: generated.manufacturerLink,
            howToLinks: generated.howToLinks?.map { LabeledLink(title: $0.title, url: $0.url) }
        )
    }

    func suggestCompanions(for tool: ToolSnapshot) async throws -> [CompanionSuggestion] {
        let details = [
            "Name: \(tool.name)",
            tool.brand.isEmpty ? nil : "Brand: \(tool.brand)",
            tool.typePath.map { "Type: \($0)" },
            tool.batteryVoltage.map { "Battery: \($0)V" },
        ].compactMap(\.self).joined(separator: ", ")

        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: "Suggest companion or complementary tools and accessories for: \(details)",
            generating: CompanionsGen.self
        )
        return response.content.companions.map {
            CompanionSuggestion(name: $0.name, reason: $0.reason, searchQuery: $0.searchQuery)
        }
    }
}
