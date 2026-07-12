import SwiftUI
import SwiftData

/// A drill-down filter for statistics: kind → taxonomy path → battery
/// platform, each level narrowing the previous one.
enum StatsFilter: Hashable {
    case disposition(Disposition)
    case kind(ToolKind)
    /// Tools whose type path starts with `path` (root name, or deeper "A › B").
    case typePath(kind: ToolKind, path: String)
    /// Battery platform (brand + label), optionally scoped to a taxonomy path.
    case battery(platform: String, kind: ToolKind?, path: String?)

    var title: String {
        switch self {
        case .disposition(let disposition): disposition.rawValue
        case .kind(let kind): "\(kind.rawValue) Tools"
        case .typePath(_, let path): path.components(separatedBy: " › ").last ?? path
        case .battery(let platform, _, _): platform
        }
    }

    func matches(_ tool: Tool) -> Bool {
        switch self {
        case .disposition(let disposition):
            return tool.disposition == disposition
        case .kind(let kind):
            return tool.disposition == .inUse && tool.kind == kind
        case .typePath(let kind, let path):
            guard tool.disposition == .inUse, tool.kind == kind,
                  let toolPath = tool.type?.path else { return false }
            return toolPath == path || toolPath.hasPrefix(path + " › ")
        case .battery(let platform, let kind, let path):
            guard tool.disposition == .inUse,
                  StatsView.batteryPlatform(of: tool) == platform else { return false }
            if let kind, tool.kind != kind { return false }
            if let path {
                guard let toolPath = tool.type?.path,
                      toolPath == path || toolPath.hasPrefix(path + " › ") else { return false }
            }
            return true
        }
    }
}

/// Roll-up statistics: totals, power vs hand, per top-level category, and
/// battery platform breakdown — every row drills into the matching tools.
struct StatsView: View {
    @Query private var tools: [Tool]

    private var active: [Tool] {
        tools.filter { $0.disposition == .inUse }
    }

    static func batteryPlatform(of tool: Tool) -> String? {
        guard let label = tool.batteryLabel else { return nil }
        return [tool.brand.isEmpty ? nil : tool.brand, label]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var body: some View {
        Form {
            Section("Overview") {
                LabeledContent("Tools In Use", value: "\(active.count)")
                statLink(
                    "Power Tools",
                    count: active.filter { $0.kind == .power }.count,
                    filter: .kind(.power)
                )
                statLink(
                    "Hand Tools",
                    count: active.filter { $0.kind == .hand }.count,
                    filter: .kind(.hand)
                )
                statLink(
                    "Sold",
                    count: tools.filter { $0.disposition == .sold }.count,
                    filter: .disposition(.sold)
                )
                statLink(
                    "Retired",
                    count: tools.filter { $0.disposition == .retired }.count,
                    filter: .disposition(.retired)
                )
            }

            Section("By Category") {
                ForEach(categoryCounts, id: \.filter) { entry in
                    statLink(entry.name, count: entry.count, filter: entry.filter)
                }
            }

            if !batteryCounts.isEmpty {
                Section("By Battery Platform") {
                    ForEach(batteryCounts, id: \.name) { entry in
                        statLink(
                            entry.name,
                            count: entry.count,
                            filter: .battery(platform: entry.name, kind: nil, path: nil)
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Statistics")
        .navigationDestination(for: StatsFilter.self) { filter in
            StatsDrillDownView(filter: filter)
        }
        .navigationDestination(for: Tool.self) { tool in
            ToolDetailView(tool: tool)
        }
    }

    @ViewBuilder
    private func statLink(_ name: String, count: Int, filter: StatsFilter) -> some View {
        NavigationLink(value: filter) {
            LabeledContent(name, value: "\(count)")
        }
    }

    private var categoryCounts: [(name: String, count: Int, filter: StatsFilter)] {
        Dictionary(grouping: active.filter { $0.type != nil && $0.kind != nil }) { tool in
            "\(tool.kind!.rawValue) › \(tool.type!.root.name)"
        }
        .map { key, value in
            let tool = value[0]
            return (
                name: key,
                count: value.count,
                filter: StatsFilter.typePath(kind: tool.kind!, path: tool.type!.root.name)
            )
        }
        .sorted { $0.name < $1.name }
    }

    private var batteryCounts: [(name: String, count: Int)] {
        Dictionary(grouping: active.compactMap { tool in
            Self.batteryPlatform(of: tool).map { (platform: $0, tool: tool) }
        }, by: \.platform)
        .map { (name: $0.key, count: $0.value.count) }
        .sorted { $0.name < $1.name }
    }
}

/// One drill level: subtype and battery breakdowns that narrow further,
/// plus the tools matching the current filter.
struct StatsDrillDownView: View {
    let filter: StatsFilter

    @Query private var tools: [Tool]

    private var matching: [Tool] {
        tools.filter { filter.matches($0) }
    }

    var body: some View {
        Form {
            if case .typePath(let kind, let path) = filter {
                let subtypes = subtypeCounts(kind: kind, path: path)
                if !subtypes.isEmpty {
                    Section("Subtypes") {
                        ForEach(subtypes, id: \.path) { entry in
                            NavigationLink(value: StatsFilter.typePath(kind: kind, path: entry.path)) {
                                LabeledContent(entry.name, value: "\(entry.count)")
                            }
                        }
                    }
                }
                let batteries = batteryCounts(kind: kind, path: path)
                if !batteries.isEmpty {
                    Section("Battery Platforms") {
                        ForEach(batteries, id: \.name) { entry in
                            NavigationLink(
                                value: StatsFilter.battery(platform: entry.name, kind: kind, path: path)
                            ) {
                                LabeledContent(entry.name, value: "\(entry.count)")
                            }
                        }
                    }
                }
            }

            Section(matching.count == 1 ? "1 Tool" : "\(matching.count) Tools") {
                ForEach(ToolQuerying.sort(matching, by: .name)) { tool in
                    NavigationLink(value: tool) {
                        ToolRowView(tool: tool)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(filter.title)
    }

    /// Counts by the next path component below `path`.
    private func subtypeCounts(kind: ToolKind, path: String) -> [(name: String, path: String, count: Int)] {
        let deeper = matching.compactMap { tool -> String? in
            guard let toolPath = tool.type?.path, toolPath != path,
                  toolPath.hasPrefix(path + " › ") else { return nil }
            let remainder = toolPath.dropFirst(path.count + 3)
            return remainder.components(separatedBy: " › ").first
        }
        return Dictionary(grouping: deeper) { $0 }
            .map { (name: $0.key, path: "\(path) › \($0.key)", count: $0.value.count) }
            .sorted { $0.name < $1.name }
    }

    private func batteryCounts(kind: ToolKind, path: String) -> [(name: String, count: Int)] {
        Dictionary(
            grouping: matching.compactMap { StatsView.batteryPlatform(of: $0) },
            by: { $0 }
        )
        .map { (name: $0.key, count: $0.value.count) }
        .sorted { $0.name < $1.name }
    }
}
