import Foundation

enum SortOption: String, CaseIterable, Identifiable {
    case type = "Type"
    case name = "Name"
    case brand = "Brand"
    case purchaseDate = "Purchase Date"
    case createdAt = "Date Added"
    case storageLocation = "Storage Location"
    case purchaseStore = "Store"
    case disposition = "Disposition"
    case powerSource = "Power Source"
    case batteryVoltage = "Battery Voltage"

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

    /// Natural order is ascending per attribute (unknown values sort first);
    /// pass ascending: false to reverse.
    static func sort(_ tools: [Tool], by option: SortOption, ascending: Bool = true) -> [Tool] {
        let sorted: [Tool] = switch option {
        case .type:
            tools.sorted { ($0.type?.path ?? "", $0.name) < ($1.type?.path ?? "", $1.name) }
        case .name:
            tools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .brand:
            tools.sorted { ($0.brand, $0.name) < ($1.brand, $1.name) }
        case .purchaseDate:
            tools.sorted { ($0.purchaseDate ?? .distantPast, $0.name) < ($1.purchaseDate ?? .distantPast, $1.name) }
        case .createdAt:
            tools.sorted { ($0.createdAt, $0.name) < ($1.createdAt, $1.name) }
        case .storageLocation:
            tools.sorted { ($0.storageLocation, $0.name) < ($1.storageLocation, $1.name) }
        case .purchaseStore:
            tools.sorted { ($0.purchaseStore, $0.name) < ($1.purchaseStore, $1.name) }
        case .disposition:
            tools.sorted { ($0.dispositionRaw, $0.name) < ($1.dispositionRaw, $1.name) }
        case .powerSource:
            tools.sorted { ($0.powerSourceRaw ?? "", $0.name) < ($1.powerSourceRaw ?? "", $1.name) }
        case .batteryVoltage:
            tools.sorted { ($0.batteryVoltage ?? Int.min, $0.name) < ($1.batteryVoltage ?? Int.min, $1.name) }
        }
        return ascending ? sorted : sorted.reversed()
    }

    /// Grouped by top-level type when sorting by type; single flat group otherwise.
    static func group(_ sorted: [Tool], by option: SortOption) -> [(key: String, tools: [Tool])] {
        guard option == .type else { return [("", sorted)] }
        return Dictionary(grouping: sorted) { $0.type?.root.name ?? "Uncategorized" }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, tools: $0.value) }
    }
}
