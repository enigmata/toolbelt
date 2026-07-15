import SwiftUI
import SwiftData

struct ToolDetailView: View {
    let tool: Tool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allTools: [Tool]
    @State private var companions: [CompanionSuggestion]?
    @State private var companionsBusy = false
    @State private var companionsError: String?
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var galleryPresentation: GalleryPresentation?

    private struct GalleryPresentation: Identifiable {
        let id = UUID()
        let index: Int
    }

    private var sortedPhotos: [ToolPhoto] {
        (tool.photos ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Form {
            if !sortedPhotos.isEmpty {
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(Array(sortedPhotos.enumerated()), id: \.offset) { index, photo in
                                Button {
                                    galleryPresentation = GalleryPresentation(index: index)
                                } label: {
                                    PhotoImage(data: photo.data)
                                        .frame(height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            Section("Identity") {
                if !tool.name.isEmpty {
                    LabeledContent("Name", value: tool.name)
                }
                if !tool.brand.isEmpty {
                    LabeledContent("Brand", value: tool.brand)
                }
                if !tool.modelName.isEmpty {
                    LabeledContent("Model", value: tool.modelName)
                }
                if !tool.modelNumber.isEmpty {
                    LabeledContent("Model Number", value: tool.modelNumber)
                }
                if !tool.serialNumber.isEmpty {
                    LabeledContent("Serial Number", value: tool.serialNumber)
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

            companionsSection
        }
        .formStyle(.grouped)
        .navigationTitle(tool.displayName)
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
        .fullScreenCover(item: $galleryPresentation) { presentation in
            PhotoGalleryView(photos: sortedPhotos, initialIndex: presentation.index)
        }
        .confirmationDialog(
            "Delete \(tool.displayName)?",
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

    // MARK: Companion suggestions

    private var companionsSection: some View {
        Section {
            if let companions {
                if companions.isEmpty {
                    Text("No suggestions.")
                        .foregroundStyle(.secondary)
                }
                ForEach(companions, id: \.self) { companion in
                    companionRow(companion)
                }
            }
            Button {
                Task { await loadCompanions() }
            } label: {
                if companionsBusy {
                    HStack {
                        ProgressView()
                        Text("Thinking…")
                    }
                } else {
                    Label(
                        companions == nil ? "Suggest Companion Tools" : "Refresh Suggestions",
                        systemImage: "sparkles"
                    )
                }
            }
            .disabled(companionsBusy)
        } header: {
            Text("Companions")
        } footer: {
            if let companionsError {
                Text(companionsError).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func companionRow(_ companion: CompanionSuggestion) -> some View {
        let owned = companion.name.flatMap { name in
            allTools.first { $0 !== tool && $0.matches(name) }
        }
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(companion.name ?? "Suggestion")
                    .font(.headline)
                Spacer()
                if let owned {
                    NavigationLink(value: owned) {
                        Text("Owned")
                            .font(.caption)
                    }
                    .fixedSize()
                } else if let query = companion.searchQuery ?? companion.name,
                          let url = shopSearchURL(for: query) {
                    Link("Find", destination: url)
                        .font(.caption)
                }
            }
            if let reason = companion.reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func loadCompanions() async {
        companionsError = nil
        companionsBusy = true
        defer { companionsBusy = false }
        do {
            companions = try await AIService.shared.suggestCompanions(for: ToolSnapshot(tool: tool))
        } catch let error as AIError {
            companionsError = error.errorDescription
        } catch {
            companionsError = error.localizedDescription
        }
    }

    private func shopSearchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: "\(query) buy")]
        return components?.url
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
