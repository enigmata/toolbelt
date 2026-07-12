import SwiftUI
import SwiftData

struct ToolDetailView: View {
    let tool: Tool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            if let photos = tool.photos, !photos.isEmpty {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(photos) { photo in
                                PhotoImage(data: photo.data)
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
            }

            Section("Identity") {
                LabeledContent("Name", value: tool.name)
                if !tool.brand.isEmpty {
                    LabeledContent("Brand", value: tool.brand)
                }
                if !tool.modelNumber.isEmpty {
                    LabeledContent("Model", value: tool.modelNumber)
                }
                if let type = tool.type {
                    LabeledContent("Type", value: "\(type.kind.rawValue) › \(type.path)")
                }
                LabeledContent("Disposition", value: tool.disposition.rawValue)
            }

            if let powerSource = tool.powerSource {
                Section("Power") {
                    LabeledContent("Source", value: powerSource.rawValue)
                    if let voltage = tool.batteryVoltage {
                        LabeledContent("Voltage", value: "\(voltage)V")
                    }
                    if let ampHours = tool.batteryAmpHours {
                        LabeledContent("Capacity", value: "\(ampHours.formatted())Ah")
                    }
                }
            }

            if tool.purchaseDate != nil || !tool.purchaseStore.isEmpty || !tool.storageLocation.isEmpty {
                Section("Purchase & Storage") {
                    if let date = tool.purchaseDate {
                        LabeledContent("Purchased", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let age = tool.ageDescription {
                        LabeledContent("Age", value: age)
                    }
                    if !tool.purchaseStore.isEmpty {
                        LabeledContent("Store", value: tool.purchaseStore)
                    }
                    if !tool.storageLocation.isEmpty {
                        LabeledContent("Stored At", value: tool.storageLocation)
                    }
                }
            }

            if manufacturerURL != nil || howToURL != nil {
                Section("Links") {
                    if let url = manufacturerURL {
                        Link("Manufacturer Specifications", destination: url)
                    }
                    if let url = howToURL {
                        Link("How-To & Videos", destination: url)
                    }
                }
            }

            if !tool.notes.isEmpty {
                Section("Tips & Notes") {
                    Text(tool.notes)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tool.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditSheet = true }
            }
            ToolbarItem {
                dispositionMenu
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            ToolFormView(tool: tool)
        }
        .confirmationDialog(
            "Delete \(tool.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                context.delete(tool)
                dismiss()
            }
        } message: {
            Text("This permanently removes the tool and its photos.")
        }
    }

    private var manufacturerURL: URL? {
        tool.manufacturerLink.isEmpty ? nil : URL(string: tool.manufacturerLink)
    }

    private var howToURL: URL? {
        tool.howToLink.isEmpty ? nil : URL(string: tool.howToLink)
    }

    private var dispositionMenu: some View {
        Menu {
            ForEach(Disposition.allCases.filter { $0 != tool.disposition }) { disposition in
                Button {
                    tool.disposition = disposition
                } label: {
                    Label("Mark \(disposition.rawValue)", systemImage: disposition.systemImage)
                }
            }
            Divider()
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete Tool", systemImage: "trash")
            }
        } label: {
            Label("Actions", systemImage: "ellipsis.circle")
        }
    }
}
