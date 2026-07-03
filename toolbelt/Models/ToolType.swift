import Foundation
import SwiftData

enum ToolKind: String, Codable, CaseIterable, Identifiable {
    case power = "Power"
    case hand = "Hand"

    var id: String { rawValue }
}

/// A node in the tool taxonomy: kind (power/hand) → type → subtype → ...
/// Arbitrary depth so e.g. Chisel → Wood → 1/2" works.
/// All properties are optional or defaulted to stay CloudKit-compatible.
@Model
final class ToolType {
    var name: String = ""
    var kindRaw: String = ToolKind.power.rawValue
    var parent: ToolType?
    @Relationship(deleteRule: .cascade, inverse: \ToolType.parent)
    var children: [ToolType]? = []
    @Relationship(deleteRule: .nullify, inverse: \Tool.type)
    var tools: [Tool]? = []

    init(name: String, kind: ToolKind, parent: ToolType? = nil) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.parent = parent
    }

    var kind: ToolKind {
        ToolKind(rawValue: root.kindRaw) ?? .power
    }

    var root: ToolType {
        parent?.root ?? self
    }

    /// Full path from the top-level type, e.g. "Chisel › Wood › 1/2\""
    var path: String {
        if let parent {
            return "\(parent.path) › \(name)"
        }
        return name
    }

    var sortedChildren: [ToolType] {
        (children ?? []).sorted { $0.name < $1.name }
    }
}
