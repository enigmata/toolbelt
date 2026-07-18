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
    static let identificationProviderKey = "identificationProviderID"

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

    /// The guard chain every AI call goes through. Uses the user's selected
    /// provider unless the caller passes an explicit override — and an
    /// override only ever comes from a choice the user just made in the UI.
    func readyProvider(_ overrideID: AIProviderID? = nil) throws -> any AIProvider {
        let targetID = overrideID ?? selectedProviderID
        guard let provider = provider(for: targetID) else {
            throw AIError.unavailable("\(targetID.shortName) is not available in this app.")
        }
        guard provider.isAvailable else {
            throw AIError.unavailable(provider.unavailabilityReason ?? "\(targetID.shortName) is unavailable.")
        }
        if provider.requiresNetwork && !isOnline {
            throw AIError.offline
        }
        if provider.requiresAPIKey && (keyLookup(provider.id) ?? "").isEmpty {
            throw AIError.missingAPIKey(provider.id)
        }
        return provider
    }

    /// The user's sticky choice for identification lookups (brand/model,
    /// barcode, packaging photo); nil until they decide. Set from the
    /// one-time provider prompt or the Lookup Provider picker in the form.
    var identificationProviderID: AIProviderID? {
        get {
            UserDefaults.standard.string(forKey: Self.identificationProviderKey)
                .flatMap(AIProviderID.init(rawValue:))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: Self.identificationProviderKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.identificationProviderKey)
            }
        }
    }

    /// Provider identification lookups run on: the sticky choice when the
    /// user has made one, else the overall selection.
    var lookupProviderID: AIProviderID {
        identificationProviderID ?? selectedProviderID
    }

    /// Identification (brand/model lookup, barcode, packaging photo) works
    /// best with web-grounded product data, which the on-device model lacks
    /// — and photo extraction it can't do at all. When the on-device model
    /// is selected and a ready cloud provider exists, this returns that
    /// provider so the UI can *offer* it. The app never switches silently;
    /// the user decides once and the choice is remembered.
    var identificationAlternative: (any AIProvider)? {
        guard selectedProviderID == .foundationModels else { return nil }
        return [AIProviderID.claude, .gemini]
            .compactMap { provider(for: $0) }
            .first { readinessIssue(for: $0) == nil }
    }

    // MARK: Facade

    func lookupToolDetails(brand: String, model: String, using providerID: AIProviderID? = nil) async throws -> ToolDetailsSuggestion {
        try await readyProvider(providerID).lookupToolDetails(brand: brand, model: model)
    }

    func lookupToolDetails(barcode: String, using providerID: AIProviderID? = nil) async throws -> ToolDetailsSuggestion {
        try await readyProvider(providerID).lookupToolDetails(barcode: barcode)
    }

    func extractDetails(fromImage jpegData: Data, using providerID: AIProviderID? = nil) async throws -> ToolDetailsSuggestion {
        try await readyProvider(providerID).extractDetails(fromImage: jpegData)
    }

    func suggestLinks(brand: String, model: String, using providerID: AIProviderID? = nil) async throws -> LinkSuggestions {
        try await readyProvider(providerID).suggestLinks(brand: brand, model: model)
    }

    func suggestCompanions(for tool: ToolSnapshot) async throws -> [CompanionSuggestion] {
        try await readyProvider().suggestCompanions(for: tool)
    }
}
