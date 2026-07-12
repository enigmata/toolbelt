import Foundation
import Network
import Observation

/// Facade over the pluggable AI providers: registry, user selection,
/// connectivity, and the readiness guard chain. AI is always additive —
/// callers surface AIError and leave manual entry fully usable.
@Observable
final class AIService {
    static let shared = AIService()

    static let selectedProviderKey = "aiProviderID"

    let providers: [any AIProvider]
    private(set) var isOnline = true
    /// Injectable for tests; defaults to Keychain.
    private let keyLookup: (AIProviderID) -> String?
    private let pathMonitor = NWPathMonitor()

    init(
        providers: [any AIProvider] = [FoundationModelsProvider(), ClaudeProvider(), GeminiProvider()],
        keyLookup: @escaping (AIProviderID) -> String? = { KeychainHelper.read(for: $0) }
    ) {
        self.providers = providers
        self.keyLookup = keyLookup
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.enigmata.toolbelt.network"))
    }

    var selectedProviderID: AIProviderID {
        get {
            UserDefaults.standard.string(forKey: Self.selectedProviderKey)
                .flatMap(AIProviderID.init(rawValue:))
                ?? defaultProviderID
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.selectedProviderKey)
        }
    }

    /// On-device model when usable, else the first configured cloud provider.
    private var defaultProviderID: AIProviderID {
        if provider(for: .foundationModels)?.isAvailable == true {
            return .foundationModels
        }
        return providers.first { $0.requiresAPIKey && keyLookup($0.id) != nil }?.id
            ?? .foundationModels
    }

    func provider(for id: AIProviderID) -> (any AIProvider)? {
        providers.first { $0.id == id }
    }

    var activeProvider: (any AIProvider)? {
        provider(for: selectedProviderID)
    }

    /// Human-readable readiness for settings UI; nil means ready.
    func readinessIssue(for provider: any AIProvider) -> String? {
        if !provider.isAvailable {
            return provider.unavailabilityReason ?? "Unavailable"
        }
        if provider.requiresNetwork && !isOnline {
            return "Offline"
        }
        if provider.requiresAPIKey && (keyLookup(provider.id) ?? "").isEmpty {
            return "API key required"
        }
        return nil
    }

    /// The guard chain every AI call goes through.
    func readyProvider() throws -> any AIProvider {
        guard let provider = activeProvider else {
            throw AIError.unavailable("No AI provider is selected.")
        }
        guard provider.isAvailable else {
            throw AIError.unavailable(provider.unavailabilityReason ?? "The selected AI provider is unavailable.")
        }
        if provider.requiresNetwork && !isOnline {
            throw AIError.offline
        }
        if provider.requiresAPIKey && (keyLookup(provider.id) ?? "").isEmpty {
            throw AIError.missingAPIKey
        }
        return provider
    }

    // MARK: Facade

    func lookupToolDetails(brand: String, model: String) async throws -> ToolDetailsSuggestion {
        try await readyProvider().lookupToolDetails(brand: brand, model: model)
    }

    func lookupToolDetails(barcode: String) async throws -> ToolDetailsSuggestion {
        try await readyProvider().lookupToolDetails(barcode: barcode)
    }

    func extractDetails(fromImage jpegData: Data) async throws -> ToolDetailsSuggestion {
        try await readyProvider().extractDetails(fromImage: jpegData)
    }

    func suggestLinks(brand: String, model: String) async throws -> LinkSuggestions {
        try await readyProvider().suggestLinks(brand: brand, model: model)
    }

    func suggestCompanions(for tool: ToolSnapshot) async throws -> [CompanionSuggestion] {
        try await readyProvider().suggestCompanions(for: tool)
    }
}
