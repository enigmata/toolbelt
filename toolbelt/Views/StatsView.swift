import SwiftUI
import SwiftData

/// Roll-up statistics: totals, power vs hand, per top-level category, and
/// battery platform breakdown (e.g. "18V 5.0Ah").
struct StatsView: View {
    @Query private var tools: [Tool]

    private var active: [Tool] {
        tools.filter { $0.disposition == .inUse }
    }

    var body: some View {
        Form {
            Section("Overview") {
                LabeledContent("Tools In Use", value: "\(active.count)")
                LabeledContent("Power Tools", value: "\(active.filter { $0.kind == .power }.count)")
                LabeledContent("Hand Tools", value: "\(active.filter { $0.kind == .hand }.count)")
                LabeledContent("Sold", value: "\(tools.filter { $0.disposition == .sold }.count)")
                LabeledContent("Retired", value: "\(tools.filter { $0.disposition == .retired }.count)")
            }

            Section("By Category") {
                ForEach(categoryCounts, id: \.name) { entry in
                    LabeledContent(entry.name, value: "\(entry.count)")
                }
            }

            if !batteryCounts.isEmpty {
                Section("By Battery Platform") {
                    ForEach(batteryCounts, id: \.name) { entry in
                        LabeledContent(entry.name, value: "\(entry.count)")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Statistics")
    }

    private var categoryCounts: [(name: String, count: Int)] {
        Dictionary(grouping: active) { tool in
            let kind = tool.kind?.rawValue ?? "Uncategorized"
            let category = tool.type?.root.name ?? "Uncategorized"
            return "\(kind) › \(category)"
        }
        .map { (name: $0.key, count: $0.value.count) }
        .sorted { $0.name < $1.name }
    }

    private var batteryCounts: [(name: String, count: Int)] {
        Dictionary(grouping: active.filter { $0.batteryLabel != nil }) { tool in
            [tool.brand.isEmpty ? nil : tool.brand, tool.batteryLabel]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        .map { (name: $0.key, count: $0.value.count) }
        .sorted { $0.name < $1.name }
    }
}
