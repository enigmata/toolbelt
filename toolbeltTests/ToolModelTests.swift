import Testing
import Foundation
import SwiftData
@testable import toolbelt

@Suite("Tool model")
struct ToolModelTests {

    // MARK: Disposition / power source accessors

    @Test func dispositionDefaultsToInUse() {
        #expect(Tool().disposition == .inUse)
    }

    @Test func garbageDispositionRawFallsBackToInUse() {
        let tool = Tool()
        tool.dispositionRaw = "Vaporized"
        #expect(tool.disposition == .inUse)
    }

    @Test func dispositionSetterUpdatesRaw() {
        let tool = Tool()
        tool.disposition = .sold
        #expect(tool.dispositionRaw == Disposition.sold.rawValue)
    }

    @Test func powerSourceNilAndGarbageRaw() {
        let tool = Tool()
        #expect(tool.powerSource == nil)
        tool.powerSourceRaw = "Steam"
        #expect(tool.powerSource == nil)
        tool.powerSource = .battery
        #expect(tool.powerSourceRaw == PowerSource.battery.rawValue)
    }

    // MARK: Display name

    @Test func displayNameJoinsBrandAndModelName() {
        let tool = Tool()
        tool.brand = "Festool"
        tool.modelName = "OSC 18"
        tool.modelNumber = "10041861"
        #expect(tool.displayName == "Festool OSC 18")
        tool.modelName = ""
        tool.modelNumber = ""
        #expect(tool.displayName == "Festool")
    }

    @Test func displayNameFallsBackToModelNumberForOldRecords() {
        let tool = Tool()
        tool.brand = "Makita"
        tool.modelNumber = "XDT16"
        #expect(tool.displayName == "Makita XDT16")
    }

    @Test func displayNamePrefersLegacyName() {
        let tool = Tool(name: "Trusty Driver")
        tool.brand = "Makita"
        #expect(tool.displayName == "Trusty Driver")
    }

    @Test func displayNameFallsBackToTypeThenPlaceholder() {
        let type = ToolType(name: "Drill", kind: .power)
        let tool = Tool(type: type)
        #expect(tool.displayName == "Drill")
        #expect(Tool().displayName == "Untitled Tool")
    }

    // MARK: Battery label

    @Test func batteryLabelNilForCordedAndUnknown() {
        let tool = Tool()
        tool.batteryVoltage = 18
        #expect(tool.batteryLabel == nil)
        tool.powerSource = .corded
        #expect(tool.batteryLabel == nil)
    }

    @Test func batteryLabelJoinsVoltageAndCapacity() {
        let tool = Tool()
        tool.powerSource = .battery
        tool.batteryVoltage = 18
        tool.batteryAmpHours = 4.0
        let label = try! #require(tool.batteryLabel)
        #expect(label.contains("18V"))
        #expect(label.contains("Ah"))
    }

    @Test func batteryLabelNilWhenBatteryHasNoSpecs() {
        let tool = Tool()
        tool.powerSource = .battery
        #expect(tool.batteryLabel == nil)
    }

    // MARK: Age

    @Test func ageDescriptionNilWithoutPurchaseDate() {
        #expect(Tool().ageDescription == nil)
    }

    @Test func ageDescriptionUnderAMonth() {
        let tool = Tool()
        tool.purchaseDate = .now
        #expect(tool.ageDescription == "Less than a month")
    }

    @Test func ageDescriptionYearsAndMonths() {
        let tool = Tool()
        tool.purchaseDate = Calendar.current.date(byAdding: .month, value: -14, to: .now)
        #expect(tool.ageDescription == "1 year, 2 months")
    }

    // MARK: Search

    @Test func emptyQueryMatchesEverything() {
        #expect(Tool().matches(""))
    }

    @Test func matchesAcrossAttributes() {
        let root = ToolType(name: "Drill", kind: .power)
        let sub = ToolType(name: "SDS Plus", kind: .power, parent: root)
        let tool = Tool(name: "Rotary Hammer", type: sub)
        tool.brand = "Festool"
        tool.storageLocation = "Garage shelf B"
        tool.powerSource = .battery
        tool.batteryVoltage = 18

        #expect(tool.matches("rotary"))         // name, case-insensitive
        #expect(tool.matches("festool"))        // brand
        #expect(tool.matches("SDS"))            // type path
        #expect(tool.matches("shelf"))          // storage location
        #expect(tool.matches("18V"))            // battery label
        #expect(tool.matches("In Use"))         // disposition
        #expect(!tool.matches("bandsaw"))
    }

    // MARK: Taxonomy tree

    @Test func typePathRootAndKind() {
        let root = ToolType(name: "Chisel", kind: .hand)
        let mid = ToolType(name: "Wood", kind: .hand, parent: root)
        let leaf = ToolType(name: "1/2\"", kind: .hand, parent: mid)

        #expect(leaf.root === root)
        #expect(leaf.kind == .hand)
        #expect(leaf.path == "Chisel › Wood › 1/2\"")
        #expect(root.path == "Chisel")
    }
}
