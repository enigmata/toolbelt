import SwiftUI

enum SidebarItem: Hashable {
    case all
    case kind(ToolKind)
    case disposition(Disposition)
    case stats
    case taxonomy
    case identify
}

struct ContentView: View {
    @State private var selection: SidebarItem? = .all
    @State private var showingAISettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Inventory") {
                    Label("All Tools", systemImage: "wrench.and.screwdriver")
                        .tag(SidebarItem.all)
                    Label("Power Tools", systemImage: "bolt.fill")
                        .tag(SidebarItem.kind(.power))
                    Label("Hand Tools", systemImage: "hammer")
                        .tag(SidebarItem.kind(.hand))
                }
                Section("Disposition") {
                    Label("Sold", systemImage: "dollarsign.circle")
                        .tag(SidebarItem.disposition(.sold))
                    Label("Retired", systemImage: "archivebox")
                        .tag(SidebarItem.disposition(.retired))
                }
                Section {
                    Label("Identify by Photo", systemImage: "camera.viewfinder")
                        .tag(SidebarItem.identify)
                    Label("Statistics", systemImage: "chart.bar")
                        .tag(SidebarItem.stats)
                    Label("Taxonomy", systemImage: "list.bullet.indent")
                        .tag(SidebarItem.taxonomy)
                }
            }
            .navigationTitle("Toolbelt")
            .toolbar {
                ToolbarItem {
                    Button {
                        showingAISettings = true
                    } label: {
                        Label("AI Settings", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingAISettings) {
                AISettingsView()
            }
        } detail: {
            NavigationStack {
                switch selection ?? .all {
                case .all:
                    ToolListView(title: "All Tools", kind: nil, disposition: .inUse)
                case .kind(let kind):
                    ToolListView(title: "\(kind.rawValue) Tools", kind: kind, disposition: .inUse)
                case .disposition(let disposition):
                    ToolListView(title: disposition.rawValue, kind: nil, disposition: disposition)
                case .stats:
                    StatsView()
                case .taxonomy:
                    TaxonomyEditorView()
                case .identify:
                    IdentifyToolView()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Tool.self, ToolType.self, ToolPhoto.self], inMemory: true)
}
