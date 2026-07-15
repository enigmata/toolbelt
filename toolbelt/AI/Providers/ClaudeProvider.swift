import Foundation

/// Anthropic Messages API backend (no official Swift SDK — raw URLSession).
/// Structured output via `output_config.format` json_schema guarantees the
/// response text is valid JSON matching the DTO.
struct ClaudeProvider: AIProvider {
    let id = AIProviderID.claude
    let requiresAPIKey = true
    let requiresNetwork = true
    var isAvailable: Bool { true }
    var unavailabilityReason: String? { nil }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let model = "claude-opus-4-8"
    private static let systemPrompt = """
        You help catalog a personal inventory of power tools and hand tools. \
        Answer only from well-established product knowledge; leave any field \
        you are not confident about as null rather than guessing. URLs must \
        be plausible official pages, or null.
        """

    // MARK: AIProvider

    func lookupToolDetails(brand: String, model: String) async throws -> ToolDetailsSuggestion {
        try await generate(
            prompt: """
                Identify this tool and fill in its details.
                Brand: \(brand)
                Model name: \(model)
                For suggestedTypePath use "Type" or "Type › Subtype" naming, \
                e.g. "Drill › SDS Plus" or "Chisel › Wood".
                """,
            schema: Self.toolDetailsSchema,
            as: ToolDetailsSuggestion.self
        )
    }

    func lookupToolDetails(barcode: String) async throws -> ToolDetailsSuggestion {
        try await generate(
            prompt: """
                A tool product barcode was scanned. Payload: \(barcode)
                If you can identify the product (UPC/EAN or encoded text), fill \
                in its details; otherwise return nulls.
                """,
            schema: Self.toolDetailsSchema,
            as: ToolDetailsSuggestion.self
        )
    }

    func extractDetails(fromImage jpegData: Data) async throws -> ToolDetailsSuggestion {
        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": jpegData.base64EncodedString(),
                ],
            ],
            [
                "type": "text",
                "text": """
                    This photo shows a tool or its retail packaging. Identify the \
                    product and fill in its details. Read brand, model name, \
                    model number, voltage, and amp-hours from the packaging \
                    where visible.
                    """,
            ],
        ]
        return try await request(content: content, schema: Self.toolDetailsSchema, as: ToolDetailsSuggestion.self)
    }

    func suggestLinks(brand: String, model: String) async throws -> LinkSuggestions {
        try await generate(
            prompt: """
                Suggest official documentation links for this tool.
                Brand: \(brand)
                Model name: \(model)
                manufacturerLink: the product or spec page on the maker's site.
                howToLinks: up to 3 how-to / tutorial video searches or pages.
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
            prompt: """
                Suggest up to 5 companion or complementary tools and accessories \
                that pair well with this tool for typical projects:
                \(details)
                searchQuery should be a short phrase for finding that tool.
                """,
            schema: Self.companionsSchema,
            as: Wrapper.self
        )
        return wrapper.companions ?? []
    }

    // MARK: Request plumbing

    private func generate<T: Decodable>(prompt: String, schema: [String: Any], as type: T.Type) async throws -> T {
        try await request(content: [["type": "text", "text": prompt]], schema: schema, as: type)
    }

    private func request<T: Decodable>(content: [[String: Any]], schema: [String: Any], as type: T.Type) async throws -> T {
        guard let apiKey = KeychainHelper.read(for: .claude) else {
            throw AIError.missingAPIKey
        }

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 2048,
            "system": Self.systemPrompt,
            "messages": [["role": "user", "content": content]],
            "output_config": ["format": ["type": "json_schema", "schema": schema]],
        ]

        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            switch http.statusCode {
            case 401: throw AIError.missingAPIKey
            case 429: throw AIError.rateLimited
            default:
                let detail = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
                throw AIError.badResponse("HTTP \(http.statusCode): \(detail)")
            }
        }

        let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
        if decoded.stop_reason == "refusal" {
            throw AIError.badResponse("The request was declined.")
        }
        guard let text = decoded.content.first(where: { $0.type == "text" })?.text,
              let jsonData = text.data(using: .utf8) else {
            throw AIError.badResponse("No text content in response.")
        }
        return try JSONDecoder().decode(T.self, from: jsonData)
    }

    private struct MessagesResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stop_reason: String?
    }

    // MARK: JSON Schemas (mirror the DTOs; all-optional via nullable types)

    private static func nullable(_ type: String) -> [String: Any] {
        ["type": [type, "null"]]
    }

    static let toolDetailsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": nullable("string"),
            "brand": nullable("string"),
            "modelName": [
                "type": ["string", "null"],
                "description": "Marketed model designation, e.g. \"XDT17\" or \"OSC 18\"",
            ],
            "modelNumber": [
                "type": ["string", "null"],
                "description": "Manufacturer article/part number, e.g. \"10041861\" — not the model name",
            ],
            "suggestedTypePath": nullable("string"),
            "powerSource": ["type": ["string", "null"], "enum": ["Corded", "Battery", NSNull()]],
            "batteryVoltage": nullable("integer"),
            "batteryAmpHours": nullable("number"),
            "manufacturerLink": nullable("string"),
            "howToLink": nullable("string"),
            "notes": nullable("string"),
        ],
        "required": [
            "name", "brand", "modelName", "modelNumber", "suggestedTypePath", "powerSource",
            "batteryVoltage", "batteryAmpHours", "manufacturerLink", "howToLink", "notes",
        ],
        "additionalProperties": false,
    ]

    static let linkSuggestionsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "manufacturerLink": nullable("string"),
            "howToLinks": [
                "type": ["array", "null"],
                "items": [
                    "type": "object",
                    "properties": [
                        "title": nullable("string"),
                        "url": nullable("string"),
                    ],
                    "required": ["title", "url"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["manufacturerLink", "howToLinks"],
        "additionalProperties": false,
    ]

    static let companionsSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "companions": [
                "type": ["array", "null"],
                "items": [
                    "type": "object",
                    "properties": [
                        "name": nullable("string"),
                        "reason": nullable("string"),
                        "searchQuery": nullable("string"),
                    ],
                    "required": ["name", "reason", "searchQuery"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["companions"],
        "additionalProperties": false,
    ]
}
