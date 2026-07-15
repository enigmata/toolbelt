import Testing
import Foundation
@testable import toolbelt

struct MockAIProvider: AIProvider {
    var id: AIProviderID = .claude
    var requiresAPIKey = true
    var requiresNetwork = true
    var isAvailable = true
    var unavailabilityReason: String?

    var suggestion = ToolDetailsSuggestion(name: "Mock Drill", brand: "MockCo")

    func lookupToolDetails(brand: String, model: String) async throws -> ToolDetailsSuggestion { suggestion }
    func lookupToolDetails(barcode: String) async throws -> ToolDetailsSuggestion { suggestion }
    func extractDetails(fromImage jpegData: Data) async throws -> ToolDetailsSuggestion { suggestion }
    func suggestLinks(brand: String, model: String) async throws -> LinkSuggestions { LinkSuggestions() }
    func suggestCompanions(for tool: ToolSnapshot) async throws -> [CompanionSuggestion] { [] }
}

@Suite("AI service guard chain")
struct AIServiceTests {
    private func makeService(
        provider: MockAIProvider,
        key: String? = "sk-test"
    ) -> AIService {
        let service = AIService(providers: [provider], keyLookup: { _ in key })
        service.selectedProviderID = provider.id
        return service
    }

    @Test func readyProviderPassesWhenAllGuardsSatisfied() throws {
        let service = makeService(provider: MockAIProvider())
        #expect(try service.readyProvider().id == .claude)
        #expect(service.readinessIssue(for: MockAIProvider()) == nil)
    }

    @Test func unavailableProviderThrows() {
        var provider = MockAIProvider()
        provider.isAvailable = false
        provider.unavailabilityReason = "Model not ready"
        let service = makeService(provider: provider)
        #expect(throws: AIError.unavailable("Model not ready")) {
            try service.readyProvider()
        }
    }

    @Test func missingKeyThrows() {
        let service = makeService(provider: MockAIProvider(), key: nil)
        #expect(throws: AIError.missingAPIKey) {
            try service.readyProvider()
        }
    }

    @Test func keylessProviderSkipsKeyGuard() throws {
        var provider = MockAIProvider()
        provider.id = .foundationModels
        provider.requiresAPIKey = false
        provider.requiresNetwork = false
        let service = makeService(provider: provider, key: nil)
        #expect(try service.readyProvider().id == .foundationModels)
    }

    @Test func facadeDelegatesToProvider() async throws {
        let service = makeService(provider: MockAIProvider())
        let suggestion = try await service.lookupToolDetails(brand: "MockCo", model: "X1")
        #expect(suggestion.name == "Mock Drill")
    }
}

@Suite("AI DTO decoding")
struct AIDTODecodingTests {
    @Test func toolDetailsDecodesFromProviderJSON() throws {
        let json = """
            {
              "name": "18V Hammer Drill",
              "brand": "Makita",
              "modelName": "XPH14",
              "modelNumber": null,
              "suggestedTypePath": "Drill › Hammer",
              "powerSource": "Battery",
              "batteryVoltage": 18,
              "batteryAmpHours": 4.0,
              "manufacturerLink": "https://makitatools.com/xph14",
              "howToLink": null,
              "notes": null
            }
            """
        let decoded = try JSONDecoder().decode(ToolDetailsSuggestion.self, from: Data(json.utf8))
        #expect(decoded.brand == "Makita")
        #expect(decoded.modelName == "XPH14")
        #expect(decoded.modelNumber == nil)
        #expect(decoded.batteryVoltage == 18)
        #expect(decoded.howToLink == nil)
    }

    @Test func allNullDetailsDecode() throws {
        let json = """
            {"name": null, "brand": null, "modelNumber": null, "suggestedTypePath": null,
             "powerSource": null, "batteryVoltage": null, "batteryAmpHours": null,
             "manufacturerLink": null, "howToLink": null, "notes": null}
            """
        let decoded = try JSONDecoder().decode(ToolDetailsSuggestion.self, from: Data(json.utf8))
        #expect(decoded == ToolDetailsSuggestion())
    }

    @Test func companionListDecodes() throws {
        let json = """
            {"companions": [
              {"name": "Drill Bit Set", "reason": "Needed for any drilling work", "searchQuery": "titanium drill bit set"},
              {"name": null, "reason": null, "searchQuery": null}
            ]}
            """
        struct Wrapper: Codable { var companions: [CompanionSuggestion]? }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))
        #expect(decoded.companions?.count == 2)
        #expect(decoded.companions?.first?.name == "Drill Bit Set")
    }

    @Test func claudeSchemasSerializeToJSON() throws {
        for schema in [ClaudeProvider.toolDetailsSchema, ClaudeProvider.linkSuggestionsSchema, ClaudeProvider.companionsSchema] {
            #expect(JSONSerialization.isValidJSONObject(schema))
        }
        for schema in [GeminiProvider.toolDetailsSchema, GeminiProvider.linkSuggestionsSchema, GeminiProvider.companionsSchema] {
            #expect(JSONSerialization.isValidJSONObject(schema))
        }
    }
}
