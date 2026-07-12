import Testing
import Foundation
@testable import toolbelt

@Suite("Tool querying")
struct ToolQueryingTests {
    private func sampleTools() -> [Tool] {
        let drill = ToolType(name: "Drill", kind: .power)
        let chisel = ToolType(name: "Chisel", kind: .hand)

        let hammerDrill = Tool(name: "Hammer Drill", type: drill)
        hammerDrill.brand = "Makita"
        hammerDrill.purchaseDate = Date(timeIntervalSince1970: 1_000_000)

        let woodChisel = Tool(name: "Bench Chisel", type: chisel)
        woodChisel.brand = "Narex"
        woodChisel.purchaseDate = Date(timeIntervalSince1970: 2_000_000)

        let soldSaw = Tool(name: "Old Saw")
        soldSaw.brand = "Ryobi"
        soldSaw.disposition = .sold

        return [hammerDrill, woodChisel, soldSaw]
    }

    @Test func filterByDisposition() {
        let filtered = ToolQuerying.filter(sampleTools(), kind: nil, disposition: .sold, searchText: "")
        #expect(filtered.map(\.name) == ["Old Saw"])
    }

    @Test func filterByKind() {
        let filtered = ToolQuerying.filter(sampleTools(), kind: .hand, disposition: .inUse, searchText: "")
        #expect(filtered.map(\.name) == ["Bench Chisel"])
    }

    @Test func filterBySearchText() {
        let filtered = ToolQuerying.filter(sampleTools(), kind: nil, disposition: .inUse, searchText: "makita")
        #expect(filtered.map(\.name) == ["Hammer Drill"])
    }

    @Test func sortByName() {
        let sorted = ToolQuerying.sort(sampleTools(), by: .name)
        #expect(sorted.map(\.name) == ["Bench Chisel", "Hammer Drill", "Old Saw"])
    }

    @Test func sortByBrand() {
        let sorted = ToolQuerying.sort(sampleTools(), by: .brand)
        #expect(sorted.map(\.brand) == ["Makita", "Narex", "Ryobi"])
    }

    @Test func sortByPurchaseDateNewestFirstWithUnknownLast() {
        let sorted = ToolQuerying.sort(sampleTools(), by: .purchaseDate)
        #expect(sorted.map(\.name) == ["Bench Chisel", "Hammer Drill", "Old Saw"])
    }

    @Test func groupByTypeUsesRootNameAndUncategorized() {
        let tools = sampleTools()
        let groups = ToolQuerying.group(ToolQuerying.sort(tools, by: .type), by: .type)
        #expect(groups.map(\.key) == ["Chisel", "Drill", "Uncategorized"])
    }

    @Test func nonTypeSortYieldsSingleFlatGroup() {
        let groups = ToolQuerying.group(sampleTools(), by: .name)
        #expect(groups.count == 1)
        #expect(groups[0].key.isEmpty)
        #expect(groups[0].tools.count == 3)
    }
}
