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
                Use web search to verify the product against the \
                manufacturer's site — especially the article/part number, \
                power specs, and product page URL. Leave anything you cannot \
                verify as null.
                For suggestedTypePath use "Type" or "Type › Subtype" naming, \
                e.g. "Drill › SDS Plus" or "Chisel › Wood".
                """,
            schema: Self.toolDetailsSchema,
            grounded: true,
            as: ToolDetailsSuggestion.self
        )
    }

    func lookupToolDetails(barcode: String) async throws -> ToolDetailsSuggestion {
        try await generate(
            prompt: """
                A tool product barcode was scanned. Payload: \(barcode)
                Search the web for this UPC/EAN to identify the product and \
                fill in its details; otherwise return nulls.
                """,
            schema: Self.toolDetailsSchema,
            grounded: true,
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
        return try await request(content: content, schema: Self.toolDetailsSchema, grounded: true, as: ToolDetailsSuggestion.self)
    }

    func suggestLinks(brand: String, model: String) async throws -> LinkSuggestions {
        try await generate(
            prompt: """
                Find official documentation links for this tool via web search.
                Brand: \(brand)
                Model name: \(model)
                manufacturerLink: the product or spec page on the maker's site.
                howToLinks: up to 3 how-to / tutorial video searches or pages.
                Only return URLs you verified exist.
                """,
            schema: Self.linkSuggestionsSchema,
            grounded: true,
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

    private func generate<T: Decodable>(prompt: String, schema: [String: Any], grounded: Bool = false, as type: T.Type) async throws -> T {
        try await request(content: [["type": "text", "text": prompt]], schema: schema, grounded: grounded, as: type)
    }

    /// `grounded` adds the server-side web_search tool so answers come from
    /// live product pages rather than model memory. The server runs the
    /// search loop; `pause_turn` means it hit its iteration limit and wants
    /// the turn re-sent to resume.
    private func request<T: Decodable>(content: [[String: Any]], schema: [String: Any], grounded: Bool = false, as type: T.Type) async throws -> T {
        guard let apiKey = KeychainHelper.read(for: .claude) else {
            throw AIError.missingAPIKey(id)
        }

        var messages: [[String: Any]] = [["role": "user", "content": content]]
        for _ in 0..<3 {
            var body: [String: Any] = [
                "model": Self.model,
                "max_tokens": 4096,
                "system": Self.systemPrompt,
                "messages": messages,
                "output_config": ["format": ["type": "json_schema", "schema": schema]],
            ]
            if grounded {
                body["tools"] = [["type": "web_search_20260209", "name": "web_search", "max_uses": 5]]
            }

            var urlRequest = URLRequest(url: Self.endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                switch http.statusCode {
                case 401: throw AIError.unauthorized(id)
                case 429: throw AIError.rateLimited(id, detail: AIError.apiErrorMessage(from: data))
                default:
                    let detail = AIError.apiErrorMessage(from: data)
                        ?? String(String(data: data, encoding: .utf8)?.prefix(200) ?? "")
                    throw AIError.badResponse(id, "HTTP \(http.statusCode): \(detail)")
                }
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let blocks = json["content"] as? [[String: Any]] else {
                throw AIError.badResponse(id, "Unexpected response shape.")
            }
            let stopReason = json["stop_reason"] as? String
            if stopReason == "refusal" {
                throw AIError.badResponse(id, "The request was declined.")
            }
            if stopReason == "pause_turn" {
                messages.append(["role": "assistant", "content": blocks])
                continue
            }

            // Web-search responses can split the answer across text blocks.
            let text = blocks
                .compactMap { block -> String? in
                    guard block["type"] as? String == "text" else { return nil }
                    return block["text"] as? String
                }
                .joined()
            guard !text.isEmpty, let jsonData = text.data(using: .utf8) else {
                throw AIError.badResponse(id, "No text content in response.")
            }
            return try JSONDecoder().decode(T.self, from: jsonData)
        }
        throw AIError.badResponse(id, "The web search did not finish. Try again.")
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
