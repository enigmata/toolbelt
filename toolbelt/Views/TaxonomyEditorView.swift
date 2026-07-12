import SwiftUI
import SwiftData

/// Add / rename / delete taxonomy types at any depth. Deleting a type
/// cascade-deletes its subtypes; tools referencing them become untyped.
struct TaxonomyEditorView: View {
    @Environment(\.modelContext) private var context
    @Query private var allTypes: [ToolType]

    @State private var renamingType: ToolType?
    @State private var addingChildTo: ToolType?
    @State private var addingRootKind: ToolKind?
    @State private var deletingType: ToolType?
    @State private var nameDraft = ""

    private func roots(for kind: ToolKind) -> [ToolType] {
        allTypes
            .filter { $0.parent == nil && $0.kindRaw == kind.rawValue }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        List {
            ForEach(ToolKind.allCases) { kind in
                Section("\(kind.rawValue) Tools") {
                    OutlineGroup(roots(for: kind), children: \.outlineChildren) { type in
                        TypeRow(type: type)
                            .contextMenu {
                                Button {
                                    nameDraft = type.name
                                    renamingType = type
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button {
                                    nameDraft = ""
                                    addingChildTo = type
                                } label: {
                                    Label("Add Subtype", systemImage: "plus")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    deletingType = type
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Taxonomy")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(ToolKind.allCases) { kind in
                        Button("Add \(kind.rawValue) Type") {
                            nameDraft = ""
                            addingRootKind = kind
                        }
                    }
                } label: {
                    Label("Add Type", systemImage: "plus")
                }
            }
        }
        .alert(
            "Rename \(renamingType?.name ?? "Type")",
            isPresented: Binding(
                get: { renamingType != nil },
                set: { if !$0 { renamingType = nil } }
            )
        ) {
            TextField("Name", text: $nameDraft)
            Button("Rename") {
                if let type = renamingType, !trimmedDraft.isEmpty {
                    type.name = trimmedDraft
                }
                renamingType = nil
            }
            Button("Cancel", role: .cancel) { renamingType = nil }
        }
        .alert(
            "Add Subtype to \(addingChildTo?.name ?? "Type")",
            isPresented: Binding(
                get: { addingChildTo != nil },
                set: { if !$0 { addingChildTo = nil } }
            )
        ) {
            TextField("Name", text: $nameDraft)
            Button("Add") {
                if let parent = addingChildTo, !trimmedDraft.isEmpty {
                    context.insert(ToolType(name: trimmedDraft, kind: parent.kind, parent: parent))
                }
                addingChildTo = nil
            }
            Button("Cancel", role: .cancel) { addingChildTo = nil }
        }
        .alert(
            "Add \(addingRootKind?.rawValue ?? "") Type",
            isPresented: Binding(
                get: { addingRootKind != nil },
                set: { if !$0 { addingRootKind = nil } }
            )
        ) {
            TextField("Name", text: $nameDraft)
            Button("Add") {
                if let kind = addingRootKind, !trimmedDraft.isEmpty {
                    context.insert(ToolType(name: trimmedDraft, kind: kind))
                }
                addingRootKind = nil
            }
            Button("Cancel", role: .cancel) { addingRootKind = nil }
        }
        .confirmationDialog(
            "Delete \(deletingType?.name ?? "Type")?",
            isPresented: Binding(
                get: { deletingType != nil },
                set: { if !$0 { deletingType = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let type = deletingType {
                    context.delete(type)
                }
                deletingType = nil
            }
        } message: {
            Text(deleteWarning)
        }
    }

    private var trimmedDraft: String {
        nameDraft.trimmingCharacters(in: .whitespaces)
    }

    private var deleteWarning: String {
        guard let type = deletingType else { return "" }
        let descendants = descendantCount(of: type)
        let tools = toolCount(of: type)
        var parts = ["This deletes the type"]
        if descendants > 0 { parts.append("and \(descendants) subtype\(descendants == 1 ? "" : "s")") }
        parts.append(".")
        if tools > 0 {
            parts.append(" \(tools) tool\(tools == 1 ? "" : "s") will become untyped.")
        }
        return parts.joined(separator: " ")
    }

    private func descendantCount(of type: ToolType) -> Int {
        (type.children ?? []).reduce(0) { $0 + 1 + descendantCount(of: $1) }
    }

    private func toolCount(of type: ToolType) -> Int {
        (type.tools?.count ?? 0) + (type.children ?? []).reduce(0) { $0 + toolCount(of: $1) }
    }
}

private struct TypeRow: View {
    let type: ToolType

    var body: some View {
        HStack {
            Text(type.name)
            Spacer()
            if let count = type.tools?.count, count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private extension ToolType {
    /// nil hides the disclosure indicator for leaf nodes in OutlineGroup.
    var outlineChildren: [ToolType]? {
        let sorted = sortedChildren
        return sorted.isEmpty ? nil : sorted
    }
}
