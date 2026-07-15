import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// CSV / JSON export of the inventory (photos excluded).
enum ExportService {
    struct ToolSnapshot: Codable, Equatable {
        var name: String
        var brand: String
        var modelName: String
        var modelNumber: String
        var serialNumber: String
        var typePath: String?
        var kind: String?
        var disposition: String
        var powerSource: String?
        var batteryVoltage: Int?
        var batteryAmpHours: Double?
        var storageLocation: String
        var purchaseDate: Date?
        var purchaseStore: String
        var manufacturerLink: String
        var howToLink: String
        var notes: String
        var createdAt: Date

        init(tool: Tool) {
            name = tool.name
            brand = tool.brand
            modelName = tool.modelName
            modelNumber = tool.modelNumber
            serialNumber = tool.serialNumber
            typePath = tool.type?.path
            kind = tool.kind?.rawValue
            disposition = tool.disposition.rawValue
            powerSource = tool.powerSource?.rawValue
            batteryVoltage = tool.batteryVoltage
            batteryAmpHours = tool.batteryAmpHours
            storageLocation = tool.storageLocation
            purchaseDate = tool.purchaseDate
            purchaseStore = tool.purchaseStore
            manufacturerLink = tool.manufacturerLink
            howToLink = tool.howToLink
            notes = tool.notes
            createdAt = tool.createdAt
        }
    }

    static let csvHeader = [
        "Name", "Brand", "Model Name", "Model Number", "Serial Number",
        "Type", "Kind", "Disposition", "Power Source",
        "Battery Voltage", "Battery Ah", "Storage Location", "Purchase Date",
        "Store", "Manufacturer Link", "How-To Link", "Notes", "Added",
    ]

    static func csv(for tools: [Tool]) -> String {
        let dateFormat = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        var rows = [csvHeader.map(escapeCSVField).joined(separator: ",")]
        for snapshot in tools.map(ToolSnapshot.init) {
            let fields: [String] = [
                snapshot.name,
                snapshot.brand,
                snapshot.modelName,
                snapshot.modelNumber,
                snapshot.serialNumber,
                snapshot.typePath ?? "",
                snapshot.kind ?? "",
                snapshot.disposition,
                snapshot.powerSource ?? "",
                snapshot.batteryVoltage.map(String.init) ?? "",
                snapshot.batteryAmpHours.map { "\($0)" } ?? "",
                snapshot.storageLocation,
                snapshot.purchaseDate.map { $0.formatted(dateFormat) } ?? "",
                snapshot.purchaseStore,
                snapshot.manufacturerLink,
                snapshot.howToLink,
                snapshot.notes,
                snapshot.createdAt.formatted(dateFormat),
            ]
            rows.append(fields.map(escapeCSVField).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func json(for tools: [Tool]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(tools.map(ToolSnapshot.init))
    }

    /// RFC 4180: quote fields containing commas, quotes, or newlines;
    /// double embedded quotes.
    static func escapeCSVField(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct CSVExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { $0.data }
            .suggestedFileName("toolbelt-inventory.csv")
    }
}

struct JSONExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("toolbelt-inventory.json")
    }
}
