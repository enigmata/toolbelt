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
        tools.filter { (tool: Tool) -> Bool in
            guard tool.disposition == disposition else { return false }
            if let kind, tool.kind != kind { return false }
            return tool.matches(searchText)
        }
    }

    /// Natural order is ascending per attribute (unknown values sort first);
    /// pass ascending: false to reverse. Comparators are explicit functions
    /// so slower compilers don't time out type-checking tuple closures.
    static func sort(_ tools: [Tool], by option: SortOption, ascending: Bool = true) -> [Tool] {
        let comparator: (Tool, Tool) -> Bool
        switch option {
        case .type: comparator = byType
        case .name: comparator = byName
        case .brand: comparator = byBrand
        case .purchaseDate: comparator = byPurchaseDate
        case .createdAt: comparator = byCreatedAt
        case .storageLocation: comparator = byStorageLocation
        case .purchaseStore: comparator = byPurchaseStore
        case .disposition: comparator = byDisposition
        case .powerSource: comparator = byPowerSource
        case .batteryVoltage: comparator = byBatteryVoltage
        }
        let sorted = tools.sorted(by: comparator)
        return ascending ? sorted : sorted.reversed()
    }

    private static func byType(_ a: Tool, _ b: Tool) -> Bool {
        let pathA: String = a.type?.path ?? ""
        let pathB: String = b.type?.path ?? ""
        if pathA != pathB { return pathA < pathB }
        return a.displayName < b.displayName
    }

    private static func byName(_ a: Tool, _ b: Tool) -> Bool {
        a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
    }

    private static func byBrand(_ a: Tool, _ b: Tool) -> Bool {
        if a.brand != b.brand { return a.brand < b.brand }
        return a.displayName < b.displayName
    }

    private static func byPurchaseDate(_ a: Tool, _ b: Tool) -> Bool {
        let dateA: Date = a.purchaseDate ?? .distantPast
        let dateB: Date = b.purchaseDate ?? .distantPast
        if dateA != dateB { return dateA < dateB }
        return a.displayName < b.displayName
    }

    private static func byCreatedAt(_ a: Tool, _ b: Tool) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return a.displayName < b.displayName
    }

    private static func byStorageLocation(_ a: Tool, _ b: Tool) -> Bool {
        if a.storageLocation != b.storageLocation { return a.storageLocation < b.storageLocation }
        return a.displayName < b.displayName
    }

    private static func byPurchaseStore(_ a: Tool, _ b: Tool) -> Bool {
        if a.purchaseStore != b.purchaseStore { return a.purchaseStore < b.purchaseStore }
        return a.displayName < b.displayName
    }

    private static func byDisposition(_ a: Tool, _ b: Tool) -> Bool {
        if a.dispositionRaw != b.dispositionRaw { return a.dispositionRaw < b.dispositionRaw }
        return a.displayName < b.displayName
    }

    private static func byPowerSource(_ a: Tool, _ b: Tool) -> Bool {
        let sourceA: String = a.powerSourceRaw ?? ""
        let sourceB: String = b.powerSourceRaw ?? ""
        if sourceA != sourceB { return sourceA < sourceB }
        return a.displayName < b.displayName
    }

    private static func byBatteryVoltage(_ a: Tool, _ b: Tool) -> Bool {
        let voltsA: Int = a.batteryVoltage ?? .min
        let voltsB: Int = b.batteryVoltage ?? .min
        if voltsA != voltsB { return voltsA < voltsB }
        return a.displayName < b.displayName
    }

    /// Grouped by top-level type when sorting by type; single flat group otherwise.
    static func group(_ sorted: [Tool], by option: SortOption) -> [(key: String, tools: [Tool])] {
        guard option == .type else { return [("", sorted)] }
        return Dictionary(grouping: sorted) { $0.type?.root.name ?? "Uncategorized" }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, tools: $0.value) }
    }
}
