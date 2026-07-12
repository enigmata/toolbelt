import Foundation

/// Google Gemini backend via the Generative Language REST API.
/// `responseSchema` + JSON mime type constrain the reply to the DTO shape.
struct GeminiProvider: AIProvider {
    let id = AIProviderID.gemini
    let requiresAPIKey = true
    let requiresNetwork = true
    var isAvailable: Bool { true }
    var unavailabilityReason: String? { nil }

    private static let model = "gemini-2.5-flash"
    private static var endpoint: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    }
    private static let systemPrompt = """
        You help catalog a personal inventory of power tools and hand tools. \
        Answer only from well-established product knowledge; leave any field \
        you are not confident about as null rather than guessing. URLs must \
        be plausible official pages, or null.
        """

    // MARK: AIProvider

    func lookupToolDetails(brand: String, model: String) async throws -> ToolDetailsSuggestion {
        try await generate(
            parts: [["text": """
                Identify this tool and fill in its details.
                Brand: \(brand)
                Model number: \(model)
                For suggestedTypePath use "Type" or "Type › Subtype" naming, \
                e.g. "Drill › SDS Plus" or "Chisel › Wood".
                """]],
            schema: Self.toolDetailsSchema,
            as: ToolDetailsSuggestion.self
        )
    }

    func lookupToolDetails(barcode: String) async throws -> ToolDetailsSuggestion {
        try await generate(
            parts: [["text": """
                A tool product barcode was scanned. Payload: \(barcode)
                If you can identify the product (UPC/EAN or encoded text), fill \
                in its details; otherwise return nulls.
                """]],
            schema: Self.toolDetailsSchema,
            as: ToolDetailsSuggestion.self
        )
    }

    func extractDetails(fromImage jpegData: Data) async throws -> ToolDetailsSuggestion {
        try await generate(
            parts: [
                ["inline_data": ["mime_type": "image/jpeg", "data": jpegData.base64EncodedString()]],
                ["text": """
                    This photo shows a tool or its retail packaging. Identify the \
                    product and fill in its details. Read brand, model number, \
                    voltage, and amp-hours from the packaging where visible.
                    """],
            ],
            schema: Self.toolDetailsSchema,
            as: ToolDetailsSuggestion.self
        )
    }

    func suggestLinks(brand: String, model: String) async throws -> LinkSuggestions {
        try await generate(
            parts: [["text": """
                Suggest official documentation links for this tool.
                Brand: \(brand)
                Model number: \(model)
                manufacturerLink: the product or spec page on the maker's site.
                howToLinks: up to 3 how-to / tutorial video searches or pages.
                """]],
            schema: Self.linkSuggestionsSchema,
            as: LinkSuggestions.self
        )
    }

    func suggestCompanions(for tool: ToolSnapshot) async throws -> [CompanionSuggestion] {
        struct Wrapper: Codable { var companions: [CompanionSuggestion]? }
        let details = [
            "Name: \(tool.name)",
            tool.brand.isEmpty ? nil : "Brand: \(tool.brand)",
            tool.modelNumber.isEmpty ? nil : "Model: \(tool.modelNumber)",
            tool.typePath.map { "Type: \($0)" },
            tool.batteryVoltage.map { "Battery: \($0)V" },
        ].compactMap(\.self).joined(separator: "\n")

        let wrapper = try await generate(
            parts: [["text": """
                Suggest up to 5 companion or complementary tools and accessories \
                that pair well with this tool for typical projects:
                \(details)
                searchQuery should be a short phrase for finding that tool.
                """]],
            schema: Self.companionsSchema,
            as: Wrapper.self
        )
        return wrapper.companions ?? []
    }

    // MARK: Request plumbing

    private func generate<T: Decodable>(parts: [[String: Any]], schema: [String: Any], as type: T.Type) async throws -> T {
        guard let apiKey = KeychainHelper.read(for: .gemini) else {
            throw AIError.missingAPIKey
        }

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": Self.systemPrompt]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schema,
            ],
        ]

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            switch http.statusCode {
            case 401, 403: throw AIError.missingAPIKey
            case 429: throw AIError.rateLimited
            default:
                let detail = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                throw AIError.badResponse("HTTP \(http.statusCode): \(detail)")
            }
        }

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        guard let text = decoded.candidates?.first?.content?.parts?.first?.text,
              let jsonData = text.data(using: .utf8) else {
            throw AIError.badResponse("No text content in response.")
        }
        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    private struct GenerateContentResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }

    // MARK: Response schemas (OpenAPI subset; nullable via "nullable": true)

    private static func nullable(_ type: String) -> [String: Any] {
        ["type": type, "nullable": true]
    }

    static let toolDetailsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": nullable("string"),
            "brand": nullable("string"),
            "modelNumber": nullable("string"),
            "suggestedTypePath": nullable("string"),
            "powerSource": ["type": "string", "nullable": true, "enum": ["Corded", "Battery"]],
            "batteryVoltage": nullable("integer"),
            "batteryAmpHours": nullable("number"),
            "manufacturerLink": nullable("string"),
            "howToLink": nullable("string"),
            "notes": nullable("string"),
        ],
    ]

    static let linkSuggestionsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "manufacturerLink": nullable("string"),
            "howToLinks": [
                "type": "array",
                "nullable": true,
                "items": [
                    "type": "object",
                    "properties": [
                        "title": nullable("string"),
                        "url": nullable("string"),
                    ],
                ],
            ],
        ],
    ]

    static let companionsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "companions": [
                "type": "array",
                "nullable": true,
                "items": [
                    "type": "object",
                    "properties": [
                        "name": nullable("string"),
                        "reason": nullable("string"),
                        "searchQuery": nullable("string"),
                    ],
                ],
            ],
        ],
    ]
}
