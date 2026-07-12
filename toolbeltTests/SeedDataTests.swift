import Testing
import Foundation
import SwiftData
@testable import toolbelt

@Suite("Seed data")
struct SeedDataTests {
    /// Callers must keep the returned container alive for the test body —
    /// holding only the mainContext lets the container (and its store)
    /// deallocate underneath it.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Tool.self, ToolType.self, ToolPhoto.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func rootTypes(in context: ModelContext) throws -> [ToolType] {
        try context.fetch(FetchDescriptor<ToolType>()).filter { $0.parent == nil }
    }

    @Test func seedsEmptyStoreOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        SeedData.seedIfNeeded(context: context)
        let expected = SeedData.powerTypes.count + SeedData.handTypes.count
        #expect(try rootTypes(in: context).count == expected)

        SeedData.seedIfNeeded(context: context)
        #expect(try rootTypes(in: context).count == expected)
    }

    @Test func fillsOnlyMissingRoots() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let preexisting = ToolType(name: "Drill", kind: .power)
        context.insert(preexisting)
        try context.save()

        SeedData.seedIfNeeded(context: context)

        let roots = try rootTypes(in: context)
        let drills = roots.filter { $0.name == "Drill" && $0.kindRaw == ToolKind.power.rawValue }
        #expect(drills.count == 1)
        #expect(drills.first === preexisting)
        #expect(roots.count == SeedData.powerTypes.count + SeedData.handTypes.count)
    }

    @Test func dedupeMergesDuplicateRootsPreservingChildrenAndTools() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let richer = ToolType(name: "Hammer", kind: .hand)
        let child = ToolType(name: "Claw", kind: .hand, parent: richer)
        context.insert(richer)
        context.insert(child)

        let duplicate = ToolType(name: "Hammer", kind: .hand)
        context.insert(duplicate)
        let orphanChild = ToolType(name: "Sledge", kind: .hand, parent: duplicate)
        context.insert(orphanChild)
        let tool = Tool(name: "Estwing 16oz", type: duplicate)
        context.insert(tool)
        try context.save()

        SeedData.dedupeRootTypes(context: context)

        let hammers = try rootTypes(in: context).filter { $0.name == "Hammer" }
        #expect(hammers.count == 1)
        let survivor = try #require(hammers.first)
        let childNames = Set((survivor.children ?? []).map(\.name))
        #expect(childNames.contains("Claw"))
        #expect(childNames.contains("Sledge"))
        #expect(tool.type === survivor)
    }
}
