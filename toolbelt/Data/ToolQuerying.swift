import Foundation

enum SortOption: String, CaseIterable, Identifiable {
    case type = "Type"
    case name = "Name"
    case brand = "Brand"
    case purchaseDate = "Purchase Date"

    var id: String { rawValue }
}

/// Pure filter/sort/group helpers shared by the list UI and tests.
/// Runs in memory over @Query results — fine at personal-inventory scale.
enum ToolQuerying {
    static func filter(
        _ tools: [Tool],
        kind: ToolKind?,
        disposition: Disposition,
        searchText: String
    ) -> [Tool] {
        tools.filter { tool in
            tool.disposition == disposition
                && (kind == nil || tool.kind == kind)
                && tool.matches(searchText)
        }
    }

    static func sort(_ tools: [Tool], by option: SortOption) -> [Tool] {
        switch option {
        case .type:
            tools.sorted { ($0.type?.path ?? "", $0.name) < ($1.type?.path ?? "", $1.name) }
        case .name:
            tools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .brand:
            tools.sorted { ($0.brand, $0.name) < ($1.brand, $1.name) }
        case .purchaseDate:
            tools.sorted { ($0.purchaseDate ?? .distantPast) > ($1.purchaseDate ?? .distantPast) }
        }
    }

    /// Grouped by top-level type when sorting by type; single flat group otherwise.
    static func group(_ sorted: [Tool], by option: SortOption) -> [(key: String, tools: [Tool])] {
        guard option == .type else { return [("", sorted)] }
        return Dictionary(grouping: sorted) { $0.type?.root.name ?? "Uncategorized" }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, tools: $0.value) }
    }
}
