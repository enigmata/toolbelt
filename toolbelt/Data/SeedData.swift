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

    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<ToolType>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        for spec in powerTypes {
            insert(spec, kind: .power, parent: nil, context: context)
        }
        for spec in handTypes {
            insert(spec, kind: .hand, parent: nil, context: context)
        }
        try? context.save()
    }

    private static func insert(_ spec: TypeSpec, kind: ToolKind, parent: ToolType?, context: ModelContext) {
        let type = ToolType(name: spec.name, kind: kind, parent: parent)
        context.insert(type)
        for child in spec.children {
            insert(child, kind: kind, parent: type, context: context)
        }
    }
}
