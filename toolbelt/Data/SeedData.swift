import Foundation
import SwiftData

/// Default taxonomy inserted on first launch. Users can add, delete, and
/// modify types afterwards; this only runs against an empty store.
enum SeedData {
    struct TypeSpec: ExpressibleByStringLiteral {
        let name: String
        var children: [TypeSpec] = []

        init(_ name: String, _ children: [TypeSpec] = []) {
            self.name = name
            self.children = children
        }

        init(stringLiteral value: String) {
            self.init(value)
        }
    }

    static let powerTypes: [TypeSpec] = [
        .init("Drill", ["SDS Max", "SDS Plus", "Hammer", "Driver", "Mixing", "Right Angle"]),
        .init("Saw", ["Circular", "Miter", "Table", "Jigsaw", "Reciprocating", "Track", "Band"]),
        .init("Sander", ["Random Orbital", "Belt", "Detail", "Sheet", "Drum"]),
        .init("Grinder", ["Angle", "Bench", "Die"]),
        .init("Router", ["Fixed Base", "Plunge", "Trim"]),
        .init("Impact", ["Impact Driver", "Impact Wrench"]),
        .init("Planer", ["Handheld", "Thickness"]),
        .init("Nailer", ["Brad", "Finish", "Framing", "Pin"]),
        .init("Rotary Tool", []),
        .init("Heat Gun", []),
        .init("Vacuum", ["Shop", "Dust Extractor"]),
    ]

    static let handTypes: [TypeSpec] = [
        .init("Chisel", [
            .init("Wood", ["1/4\"", "1/2\"", "3/4\"", "1\"", "14mm"]),
            "Masonry",
            "Demolition",
        ]),
        .init("Hammer", ["Claw", "Ball-Peen", "Sledge", "Dead Blow", "Mallet"]),
        .init("Screwdriver", ["Flat", "Phillips", "Torx", "Hex", "Square"]),
        .init("Wrench", ["Adjustable", "Combination", "Socket", "Torque", "Pipe", "Allen"]),
        .init("Pliers", ["Needle-Nose", "Slip-Joint", "Locking", "Diagonal Cutting", "Linesman"]),
        .init("Saw", ["Hand", "Hack", "Coping", "Japanese Pull"]),
        .init("Clamp", ["Bar", "C-Clamp", "Spring", "Pipe", "Parallel"]),
        .init("Measuring", ["Tape Measure", "Level", "Square", "Caliper", "Marking Gauge"]),
        .init("File", ["Flat", "Round", "Half-Round", "Rasp"]),
        .init("Pry Bar", []),
        .init("Utility Knife", []),
    ]

    /// Seeds any default root types missing from the store. Per-root (rather
    /// than empty-store-only) so a device that launches before its first
    /// CloudKit import doesn't recreate the whole taxonomy, and merges
    /// duplicate roots left behind when two offline devices both seeded.
    static func seedIfNeeded(context: ModelContext) {
        dedupeRootTypes(context: context)

        let all = (try? context.fetch(FetchDescriptor<ToolType>())) ?? []
        let existingRoots = Set(
            all.filter { $0.parent == nil }.map { "\($0.kindRaw)|\($0.name)" }
        )

        var inserted = false
        for spec in powerTypes where !existingRoots.contains("\(ToolKind.power.rawValue)|\(spec.name)") {
            insert(spec, kind: .power, parent: nil, context: context)
            inserted = true
        }
        for spec in handTypes where !existingRoots.contains("\(ToolKind.hand.rawValue)|\(spec.name)") {
            insert(spec, kind: .hand, parent: nil, context: context)
            inserted = true
        }
        if inserted {
            try? context.save()
        }
    }

    /// Merges duplicate root types with the same kind and name: the root with
    /// the most descendants survives; the others' children and tools are
    /// re-parented onto it before deletion.
    static func dedupeRootTypes(context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<ToolType>())) ?? []
        let roots = all.filter { $0.parent == nil }
        let grouped = Dictionary(grouping: roots) { "\($0.kindRaw)|\($0.name)" }

        var merged = false
        for (_, duplicates) in grouped where duplicates.count > 1 {
            let ranked = duplicates.sorted {
                (($0.children?.count ?? 0) + ($0.tools?.count ?? 0))
                    > (($1.children?.count ?? 0) + ($1.tools?.count ?? 0))
            }
            let keeper = ranked[0]
            for loser in ranked.dropFirst() {
                for child in loser.children ?? [] {
                    child.parent = keeper
                }
                for tool in loser.tools ?? [] {
                    tool.type = keeper
                }
                context.delete(loser)
                merged = true
            }
        }
        if merged {
            try? context.save()
        }
    }

    private static func insert(_ spec: TypeSpec, kind: ToolKind, parent: ToolType?, context: ModelContext) {
        let type = ToolType(name: spec.name, kind: kind, parent: parent)
        context.insert(type)
        for child in spec.children {
            insert(child, kind: kind, parent: type, context: context)
        }
    }
}
