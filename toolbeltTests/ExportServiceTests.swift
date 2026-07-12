import Testing
import Foundation
@testable import toolbelt

@Suite("Export service")
struct ExportServiceTests {

    // MARK: CSV escaping

    @Test func plainFieldsPassThrough() {
        #expect(ExportService.escapeCSVField("Makita") == "Makita")
    }

    @Test func fieldsWithCommasAreQuoted() {
        #expect(ExportService.escapeCSVField("shelf, garage") == "\"shelf, garage\"")
    }

    @Test func embeddedQuotesAreDoubled() {
        #expect(ExportService.escapeCSVField("1/2\" chisel") == "\"1/2\"\" chisel\"")
    }

    @Test func newlinesAreQuoted() {
        #expect(ExportService.escapeCSVField("line1\nline2") == "\"line1\nline2\"")
    }

    // MARK: CSV document

    @Test func csvHasHeaderAndOneRowPerTool() {
        let drill = Tool(name: "Drill, cordless")
        drill.brand = "DeWalt"
        let saw = Tool(name: "Saw")

        let csv = ExportService.csv(for: [drill, saw])
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0].hasPrefix("Name,Brand"))
        #expect(lines[1].hasPrefix("\"Drill, cordless\",DeWalt"))
    }

    // MARK: JSON round-trip

    @Test func jsonRoundTripsSnapshotFields() throws {
        let root = ToolType(name: "Drill", kind: .power)
        let tool = Tool(name: "Hammer Drill", type: root)
        tool.brand = "Makita"
        tool.powerSource = .battery
        tool.batteryVoltage = 18
        tool.purchaseDate = Date(timeIntervalSince1970: 1_700_000_000)
        // ISO 8601 drops sub-second precision; whole seconds keep the
        // round-trip comparison exact.
        tool.createdAt = Date(timeIntervalSince1970: 1_710_000_000)

        let data = try ExportService.json(for: [tool])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([ExportService.ToolSnapshot].self, from: data)

        #expect(decoded.count == 1)
        #expect(decoded[0] == ExportService.ToolSnapshot(tool: tool))
        #expect(decoded[0].batteryVoltage == 18)
        #expect(decoded[0].typePath == "Drill")
    }
}
