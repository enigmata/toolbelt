import SwiftUI
import SwiftData

struct ToolListView: View {
    let title: String
    let kind: ToolKind?
    let disposition: Disposition

    @Environment(\.modelContext) private var context
    @Query(sort: \Tool.name) private var tools: [Tool]
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var toolPendingDelete: Tool?
    // Spec: any sort order can be saved as the default, so persist it.
    @AppStorage("defaultSortOption") private var sortRaw = SortOption.type.rawValue

    private var sortOption: SortOption {
        SortOption(rawValue: sortRaw) ?? .type
    }

    private var filtered: [Tool] {
        ToolQuerying.filter(tools, kind: kind, disposition: disposition, searchText: searchText)
    }

    private var groups: [(key: String, tools: [Tool])] {
        ToolQuerying.group(ToolQuerying.sort(filtered, by: sortOption), by: sortOption)
    }

    var body: some View {
        List {
            if !filtered.isEmpty {
                summarySection
            }
            ForEach(groups, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.tools) { tool in
                        NavigationLink(value: tool) {
                            ToolRowView(tool: tool)
                        }
                        .contextMenu { contextMenu(for: tool) }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationDestination(for: Tool.self) { tool in
            ToolDetailView(tool: tool)
        }
        .searchable(text: $searchText, prompt: "Search any attribute")
        .overlay {
            if filtered.isEmpty {
                emptyState
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Tool", systemImage: "plus")
                }
            }
            ToolbarItem {
                sortMenu
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ToolFormView()
        }
        .confirmationDialog(
            "Delete \(toolPendingDelete?.name ?? "Tool")?",
            isPresented: Binding(
                get: { toolPendingDelete != nil },
                set: { if !$0 { toolPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let tool = toolPendingDelete {
                    context.delete(tool)
                }
                toolPendingDelete = nil
            }
        } message: {
            Text("This permanently removes the tool and its photos.")
        }
    }

    private var summarySection: some View {
        Section {
            let power = filtered.filter { $0.kind == .power }.count
            let hand = filtered.filter { $0.kind == .hand }.count
            Text("\(filtered.count) tools · \(power) power · \(hand) hand")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortRaw) {
                ForEach(SortOption.allCases) { option in
                    Text(option.rawValue).tag(option.rawValue)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
    }

    @ViewBuilder
    private func contextMenu(for tool: Tool) -> some View {
        ForEach(Disposition.allCases.filter { $0 != tool.disposition }) { disposition in
            Button {
                tool.disposition = disposition
            } label: {
                Label("Mark \(disposition.rawValue)", systemImage: disposition.systemImage)
            }
        }
        Divider()
        Button(role: .destructive) {
            toolPendingDelete = tool
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Tools", systemImage: "wrench.and.screwdriver")
        } description: {
            Text(searchText.isEmpty
                 ? "Add your first tool to get started."
                 : "No tools match “\(searchText)”.")
        } actions: {
            if searchText.isEmpty {
                Button("Add Tool") { showingAddSheet = true }
            }
        }
    }
}

struct ToolRowView: View {
    let tool: Tool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = tool.batteryLabel {
                Text(battery)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
            }
        }
    }

    private var subtitle: String {
        [tool.brand, tool.type?.path]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
