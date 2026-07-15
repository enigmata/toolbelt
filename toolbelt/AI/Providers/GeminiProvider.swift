import Foundation

/// Google Gemini backend via the Generative Language REST API.
/// `responseSchema` + JSON mime type constrain the reply to the DTO shape.
struct GeminiProvider: AIProvider {
    let id = AIProviderID.gemini
    let requiresAPIKey = true
    let requiresNetwork = true
    var isAvailable: Bool { true }
    var unavailabilityReason: String? { nil }

    // Gemini 2.x is closed to new API users; keep this on the current
    // stable flash model (Google 404s retired IDs with an explicit message).
    private static let model = "gemini-3.5-flash"
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
        try await groundedGenerate(
            question: """
                Research this tool online.
                Brand: \(brand)
                Model name: \(model)
                Report, from the manufacturer's site where possible: full \
                product name, manufacturer article/part number, tool category \
                and subtype, corded or battery, battery voltage and amp-hours, \
                official product page URL, a how-to video URL, and one usage \
                tip. Say "unknown" for anything you cannot verify.
                """,
            schema: Self.toolDetailsSchema,
            as: ToolDetailsSuggestion.self
        )
    }

    func lookupToolDetails(barcode: String) async throws -> ToolDetailsSuggestion {
        try await groundedGenerate(
            question: """
                A tool product barcode was scanned. Payload: \(barcode)
                Search for this UPC/EAN online. If it identifies a product, \
                report its brand, model name, article number, category, power \
                specs, and official product page; otherwise say "unknown".
                """,
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
                    product and fill in its details. Read brand, model name, \
                    model number, voltage, and amp-hours from the packaging \
                    where visible.
                    """],
            ],
            schema: Self.toolDetailsSchema,
            as: ToolDetailsSuggestion.self
        )
    }

    func suggestLinks(brand: String, model: String) async throws -> LinkSuggestions {
        try await groundedGenerate(
            question: """
                Find documentation links online for this tool.
                Brand: \(brand)
                Model name: \(model)
                Report the official product or spec page on the maker's site \
                and up to 3 how-to / tutorial videos or pages, with titles \
                and URLs. Only list URLs you found in search results.
                """,
            schema: Self.linkSuggestionsSchema,
            as: LinkSuggestions.self
        )
    }

    func suggestCompanions(for tool: ToolSnapshot) async throws -> [CompanionSuggestion] {
        struct Wrapper: Codable { var companions: [CompanionSuggestion]? }
        let details = [
            "Name: \(tool.name)",
            tool.brand.isEmpty ? nil : "Brand: \(tool.brand)",
            tool.modelName.isEmpty ? nil : "Model: \(tool.modelName)",
            tool.modelNumber.isEmpty ? nil : "Model number: \(tool.modelNumber)",
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
        let text = try await send(body: [
            "system_instruction": ["parts": [["text": Self.systemPrompt]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schema,
            ],
        ])
        guard let jsonData = text.data(using: .utf8) else {
            throw AIError.badResponse("No text content in response.")
        }
        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    /// Gemini rejects Google Search grounding combined with a response
    /// schema in one call, so grounded lookups run in two steps: a search
    /// call that gathers verified facts as text, then a schema-constrained
    /// call that structures them.
    private func groundedGenerate<T: Decodable>(question: String, schema: [String: Any], as type: T.Type) async throws -> T {
        let notes = try await send(body: [
            "system_instruction": ["parts": [["text": Self.systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": question]]]],
            "tools": [["google_search": [:]]],
        ])
        return try await generate(
            parts: [["text": """
                Fill in the JSON fields using only these verified research \
                notes. Leave anything the notes don't cover as null.

                \(notes)
                """]],
            schema: schema,
            as: type
        )
    }

    private func send(body: [String: Any]) async throws -> String {
        guard let apiKey = KeychainHelper.read(for: .gemini) else {
            throw AIError.missingAPIKey
        }

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            switch http.statusCode {
            case 401: throw AIError.missingAPIKey
            case 429: throw AIError.rateLimited
            default:
                // 403 stays here too: Google uses it for disabled APIs,
                // key restrictions, and billing — not just missing keys,
                // so surface the real message instead of "add a key".
                let detail = String(data: data, encoding: .utf8)?.prefix(300) ?? ""
                throw AIError.badResponse("HTTP \(http.statusCode): \(detail)")
            }
        }

        let decoded = try JSONDecoder().decode(GenerateContentResponse.self, from: data)
        let text = (decoded.candidates?.first?.content?.parts ?? [])
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty else {
            throw AIError.badResponse("No text content in response.")
        }
        return text
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
            "modelName": [
                "type": "string", "nullable": true,
                "description": "Marketed model designation, e.g. \"XDT17\" or \"OSC 18\"",
            ],
            "modelNumber": [
                "type": "string", "nullable": true,
                "description": "Manufacturer article/part number, e.g. \"10041861\" — not the model name",
            ],
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
