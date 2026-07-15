import SwiftUI
import SwiftData
import PhotosUI

/// Add/edit form. Pass an existing tool to edit; omit to create.
/// TODO(spec): auto-populate details from brand/model lookup, QR/bar code
/// scan, or a photo of the packaging.
struct ToolFormView: View {
    let tool: Tool?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ToolType.name) private var allTypes: [ToolType]

    @State private var brand: String
    @State private var modelName: String
    @State private var modelNumber: String
    @State private var serialNumber: String
    @State private var selectedType: ToolType?
    @State private var powerSource: PowerSource?
    @State private var batteryVoltage: Int?
    @State private var batteryAmpHours: Double?
    @State private var storageLocation: String
    @State private var hasPurchaseDate: Bool
    @State private var purchaseDate: Date
    @State private var purchaseStore: String
    @State private var manufacturerLink: String
    @State private var howToLink: String
    @State private var notes: String
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var newPhotoData: [Data] = []
    @State private var photosToDelete: [ToolPhoto] = []
    @State private var showingCamera = false
    @State private var showingScanner = false
    @State private var showingPackagingCamera = false
    @State private var aiBusy = false
    @State private var aiErrorMessage: String?
    @State private var pendingSuggestion: PendingSuggestion?

    struct PendingSuggestion: Identifiable {
        let id = UUID()
        let suggestion: ToolDetailsSuggestion
    }

    init(tool: Tool? = nil) {
        self.tool = tool
        _brand = State(initialValue: tool?.brand ?? "")
        _modelName = State(initialValue: tool?.modelName ?? "")
        _modelNumber = State(initialValue: tool?.modelNumber ?? "")
        _serialNumber = State(initialValue: tool?.serialNumber ?? "")
        _selectedType = State(initialValue: tool?.type)
        _powerSource = State(initialValue: tool?.powerSource)
        _batteryVoltage = State(initialValue: tool?.batteryVoltage)
        _batteryAmpHours = State(initialValue: tool?.batteryAmpHours)
        _storageLocation = State(initialValue: tool?.storageLocation ?? "")
        _hasPurchaseDate = State(initialValue: tool?.purchaseDate != nil)
        _purchaseDate = State(initialValue: tool?.purchaseDate ?? .now)
        _purchaseStore = State(initialValue: tool?.purchaseStore ?? "")
        _manufacturerLink = State(initialValue: tool?.manufacturerLink ?? "")
        _howToLink = State(initialValue: tool?.howToLink ?? "")
        _notes = State(initialValue: tool?.notes ?? "")
    }

    /// Brand and model name identify a tool and are mandatory; model and
    /// serial numbers are desired but optional. Legacy records identified
    /// only by name stay editable.
    private var canSave: Bool {
        let hasBrand = !brand.trimmingCharacters(in: .whitespaces).isEmpty
        let hasModelName = !modelName.trimmingCharacters(in: .whitespaces).isEmpty
        return (hasBrand && hasModelName) || !(tool?.name ?? "").isEmpty
    }

    private var sortedTypes: [ToolType] {
        allTypes.sorted { (a: ToolType, b: ToolType) -> Bool in
            let kindA: String = a.kind.rawValue
            let kindB: String = b.kind.rawValue
            if kindA != kindB { return kindA < kindB }
            return a.path < b.path
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Brand", text: $brand)
                        .onSubmit(lookUpIfReady)
                    HStack {
                        TextField("Model Name", text: $modelName)
                            .onSubmit(lookUpIfReady)
                        if aiBusy {
                            ProgressView()
                        } else {
                            Button {
                                lookUpBrandModel()
                            } label: {
                                Image(systemName: "sparkle.magnifyingglass")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!canLookUp)
                            .accessibilityLabel("Look Up Brand + Model")
                        }
                    }
                    TextField("Model Number", text: $modelNumber)
                    TextField("Serial Number", text: $serialNumber)
                    Picker("Type", selection: $selectedType) {
                        Text("None").tag(ToolType?.none)
                        ForEach(sortedTypes) { type in
                            Text("\(type.kind.rawValue) › \(type.path)")
                                .tag(Optional(type))
                        }
                    }
                } header: {
                    Text("Identity")
                } footer: {
                    lookupStatusFooter
                }

                autoFillSection

                if selectedType?.kind == .power {
                    Section("Power") {
                        Picker("Power Source", selection: $powerSource) {
                            Text("Unknown").tag(PowerSource?.none)
                            ForEach(PowerSource.allCases) { source in
                                Text(source.rawValue).tag(Optional(source))
                            }
                        }
                        if powerSource == .battery {
                            TextField("Voltage (V)", value: $batteryVoltage, format: .number)
                            TextField("Capacity (Ah)", value: $batteryAmpHours, format: .number)
                        }
                    }
                }

                Section("Purchase & Storage") {
                    Toggle("Purchase Date Known", isOn: $hasPurchaseDate)
                    if hasPurchaseDate {
                        DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                    }
                    TextField("Store", text: $purchaseStore)
                    TextField("Storage Location", text: $storageLocation)
                }

                Section("Links") {
                    TextField("Manufacturer Specifications URL", text: $manufacturerLink)
                    TextField("How-To / Video URL", text: $howToLink)
                }

                Section("Tips & Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Photos") {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                        Label("Add Photos", systemImage: "photo.badge.plus")
                    }
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    if !remainingPhotos.isEmpty || !newPhotoData.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(remainingPhotos) { photo in
                                    photoThumbnail(data: photo.data) {
                                        photosToDelete.append(photo)
                                    }
                                }
                                ForEach(Array(newPhotoData.enumerated()), id: \.offset) { index, data in
                                    photoThumbnail(data: data) {
                                        newPhotoData.remove(at: index)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(tool == nil ? "Add Tool" : "Edit Tool")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .task(id: pickerItems) {
                await loadPickedPhotos()
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCaptureView { data in
                    newPhotoData.append(data)
                }
            }
            .fullScreenCover(isPresented: $showingPackagingCamera) {
                CameraCaptureView { data in
                    Task { await extractFromPhoto(data) }
                }
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView { payload in
                    Task { await lookup { try await AIService.shared.lookupToolDetails(barcode: payload) } }
                }
            }
            .sheet(item: $pendingSuggestion) { pending in
                SuggestionReviewView(
                    entries: reviewEntries(for: pending.suggestion),
                    onApply: {
                        apply(pending.suggestion)
                        pendingSuggestion = nil
                    },
                    onCancel: { pendingSuggestion = nil }
                )
            }
        }
    }

    // MARK: Auto-fill

    /// Lookup status lives directly under the Brand/Model fields so busy
    /// state and errors are visible where the lookup was triggered, instead
    /// of below the fold in the Auto-Fill section.
    @ViewBuilder
    private var lookupStatusFooter: some View {
        if let aiErrorMessage {
            Text(aiErrorMessage)
                .foregroundStyle(.orange)
        } else if aiBusy {
            Text("Asking \((try? AIService.shared.identificationProvider())?.displayName ?? "AI")…")
        } else {
            Text("Enter brand and model name, then hit return or the magnifying glass to look up the rest automatically.")
        }
    }

    private var canLookUp: Bool {
        !brand.trimmingCharacters(in: .whitespaces).isEmpty
            && !modelName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Keyboard-submit trigger: fires only when both fields are filled and
    /// no lookup is already running, so hitting return early is harmless.
    private func lookUpIfReady() {
        guard canLookUp, !aiBusy else { return }
        lookUpBrandModel()
    }

    private func lookUpBrandModel() {
        Task {
            await lookup {
                var suggestion = try await AIService.shared.lookupToolDetails(brand: brand, model: modelName)
                // Top up missing links when the form has none yet.
                if manufacturerLink.isEmpty, howToLink.isEmpty,
                   suggestion.manufacturerLink == nil || suggestion.howToLink == nil {
                    if let links = try? await AIService.shared.suggestLinks(brand: brand, model: modelName) {
                        suggestion.manufacturerLink = suggestion.manufacturerLink ?? links.manufacturerLink
                        suggestion.howToLink = suggestion.howToLink ?? links.howToLinks?.first?.url
                    }
                }
                return suggestion
            }
        }
    }

    private var autoFillSection: some View {
        Section {
            Button {
                showingScanner = true
            } label: {
                Label("Scan Barcode", systemImage: "barcode.viewfinder")
            }

            Button {
                showingPackagingCamera = true
            } label: {
                Label("From Packaging Photo", systemImage: "camera.viewfinder")
            }
        } header: {
            Text("Auto-Fill")
        } footer: {
            Text("Suggestions fill empty fields only; review before applying. Configure the provider in AI Settings.")
        }
    }

    private func lookup(_ operation: () async throws -> ToolDetailsSuggestion) async {
        aiErrorMessage = nil
        aiBusy = true
        defer { aiBusy = false }
        do {
            let suggestion = try await operation()
            if reviewEntries(for: suggestion).isEmpty {
                aiErrorMessage = "No new details found — fields already filled or nothing recognized."
            } else {
                pendingSuggestion = PendingSuggestion(suggestion: suggestion)
            }
        } catch let error as AIError {
            aiErrorMessage = error.errorDescription
        } catch {
            aiErrorMessage = error.localizedDescription
        }
    }

    private func extractFromPhoto(_ data: Data) async {
        guard let downscaled = downscaledJPEG(from: data) else {
            aiErrorMessage = "Couldn't read the photo."
            return
        }
        await lookup { try await AIService.shared.extractDetails(fromImage: downscaled) }
    }

    private func downscaledJPEG(from data: Data, maxDimension: CGFloat = 1568) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension else {
            return image.jpegData(compressionQuality: 0.7)
        }
        let scale = maxDimension / largest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }

    /// Suggested values that would land in currently-empty fields.
    private func reviewEntries(for suggestion: ToolDetailsSuggestion) -> [(label: String, value: String)] {
        var entries: [(String, String)] = []
        func add(_ label: String, _ value: String?, ifEmpty current: String) {
            if let value, !value.isEmpty, current.trimmingCharacters(in: .whitespaces).isEmpty {
                entries.append((label, value))
            }
        }
        add("Brand", suggestion.brand, ifEmpty: brand)
        add("Model Name", suggestion.modelName, ifEmpty: modelName)
        add("Model Number", suggestion.modelNumber, ifEmpty: modelNumber)
        if selectedType == nil, let path = suggestion.suggestedTypePath,
           matchType(forPath: path) != nil {
            entries.append(("Type", path))
        }
        if powerSource == nil, let source = suggestion.powerSource,
           PowerSource(rawValue: source) != nil {
            entries.append(("Power Source", source))
        }
        if batteryVoltage == nil, let volts = suggestion.batteryVoltage {
            entries.append(("Voltage", "\(volts)V"))
        }
        if batteryAmpHours == nil, let ampHours = suggestion.batteryAmpHours {
            entries.append(("Capacity", "\(ampHours.formatted())Ah"))
        }
        add("Manufacturer Link", suggestion.manufacturerLink, ifEmpty: manufacturerLink)
        add("How-To Link", suggestion.howToLink, ifEmpty: howToLink)
        add("Notes", suggestion.notes, ifEmpty: notes)
        return entries
    }

    private func apply(_ suggestion: ToolDetailsSuggestion) {
        func fill(_ current: inout String, with value: String?) {
            if current.trimmingCharacters(in: .whitespaces).isEmpty, let value, !value.isEmpty {
                current = value
            }
        }
        fill(&brand, with: suggestion.brand)
        fill(&modelName, with: suggestion.modelName)
        fill(&modelNumber, with: suggestion.modelNumber)
        if selectedType == nil, let path = suggestion.suggestedTypePath {
            selectedType = matchType(forPath: path)
        }
        if powerSource == nil, let source = suggestion.powerSource {
            powerSource = PowerSource(rawValue: source)
        }
        if batteryVoltage == nil { batteryVoltage = suggestion.batteryVoltage }
        if batteryAmpHours == nil { batteryAmpHours = suggestion.batteryAmpHours }
        fill(&manufacturerLink, with: suggestion.manufacturerLink)
        fill(&howToLink, with: suggestion.howToLink)
        fill(&notes, with: suggestion.notes)
    }

    /// Case-insensitive taxonomy match: full path first, then the last
    /// component, then the root name.
    private func matchType(forPath path: String) -> ToolType? {
        let lowered = path.lowercased()
        if let exact = allTypes.first(where: { $0.path.lowercased() == lowered }) {
            return exact
        }
        if let leaf = path.components(separatedBy: " › ").last?.lowercased(),
           let byLeaf = allTypes.first(where: { $0.name.lowercased() == leaf }) {
            return byLeaf
        }
        if let rootName = path.components(separatedBy: " › ").first?.lowercased() {
            return allTypes.first { $0.parent == nil && $0.name.lowercased() == rootName }
        }
        return nil
    }

    /// Existing photos minus those marked for removal; deletion is deferred
    /// to save() so Cancel is non-destructive.
    private var remainingPhotos: [ToolPhoto] {
        (tool?.photos ?? [])
            .filter { photo in !photosToDelete.contains { $0 === photo } }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func photoThumbnail(data: Data, onRemove: @escaping () -> Void) -> some View {
        PhotoImage(data: data)
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
    }

    private func loadPickedPhotos() async {
        guard !pickerItems.isEmpty else { return }
        var loaded: [Data] = []
        for item in pickerItems {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(data)
            }
        }
        pickerItems = []
        newPhotoData.append(contentsOf: loaded)
    }

    private func save() {
        let target = tool ?? Tool()
        target.brand = brand
        target.modelName = modelName
        target.modelNumber = modelNumber
        target.serialNumber = serialNumber
        target.type = selectedType
        target.powerSource = selectedType?.kind == .power ? powerSource : nil
        target.batteryVoltage = powerSource == .battery ? batteryVoltage : nil
        target.batteryAmpHours = powerSource == .battery ? batteryAmpHours : nil
        target.storageLocation = storageLocation
        target.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        target.purchaseStore = purchaseStore
        target.manufacturerLink = manufacturerLink
        target.howToLink = howToLink
        target.notes = notes
        if tool == nil {
            context.insert(target)
        }
        for photo in photosToDelete {
            context.delete(photo)
        }
        for data in newPhotoData {
            let photo = ToolPhoto(data: data)
            context.insert(photo)
            photo.tool = target
        }
        dismiss()
    }
}
