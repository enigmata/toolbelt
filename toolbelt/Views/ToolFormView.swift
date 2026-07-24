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
    @State private var kit: String
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
    @State private var activeLookupProvider: AIProviderID?
    @State private var providerPrompt: ProviderPrompt?
    @State private var failedLookup: FailedLookup?
    @State private var lookupProviderID: AIProviderID = AIService.shared.lookupProviderID

    struct PendingSuggestion: Identifiable {
        let id = UUID()
        let suggestion: ToolDetailsSuggestion
    }

    enum LookupKind {
        case brandModel
        case barcode(String)
        case packagingPhoto(Data)

        var isPhoto: Bool {
            if case .packagingPhoto = self { return true }
            return false
        }
    }

    /// Asks the user whether to run an identification lookup on a better-
    /// suited cloud provider instead of the selected on-device model.
    /// `storesChoice` makes the answer the sticky lookup default; the
    /// per-photo fallback prompt leaves the default alone.
    struct ProviderPrompt: Identifiable {
        let id = UUID()
        let kind: LookupKind
        let alternative: AIProviderID
        let storesChoice: Bool
    }

    struct FailedLookup {
        let kind: LookupKind
        let provider: AIProviderID
    }

    init(tool: Tool? = nil) {
        self.tool = tool
        _brand = State(initialValue: tool?.brand ?? "")
        _modelName = State(initialValue: tool?.modelName ?? "")
        _modelNumber = State(initialValue: tool?.modelNumber ?? "")
        _serialNumber = State(initialValue: tool?.serialNumber ?? "")
        _kit = State(initialValue: tool?.kit ?? "")
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
                    TextField("Kit / Combo", text: $kit)
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
                    // Same dismissal race as the barcode sheet: give the
                    // cover time to close before presenting a prompt.
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        extractFromPhoto(data)
                    }
                }
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView { payload in
                    // Let the sheet finish dismissing before a provider
                    // prompt may need to present, or SwiftUI drops it.
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        requestLookup(.barcode(payload))
                    }
                }
            }
            .sheet(item: $pendingSuggestion) { pending in
                SuggestionReviewView(
                    entries: reviewEntries(for: pending.suggestion),
                    modelNumberOptions: modelNumberChoices(for: pending.suggestion),
                    onApply: { fields, chosenNumber in
                        apply(pending.suggestion, fields: fields, chosenModelNumber: chosenNumber)
                        pendingSuggestion = nil
                    },
                    onCancel: { pendingSuggestion = nil }
                )
            }
            .confirmationDialog(
                "Choose AI Provider",
                isPresented: Binding(
                    get: { providerPrompt != nil },
                    set: { if !$0 { providerPrompt = nil } }
                ),
                titleVisibility: .visible,
                presenting: providerPrompt
            ) { prompt in
                Button("Use \(prompt.alternative.displayName)") {
                    if prompt.storesChoice { setLookupProvider(prompt.alternative) }
                    startLookup(prompt.kind, using: prompt.alternative)
                }
                if !prompt.kind.isPhoto {
                    Button("Use \(AIService.shared.selectedProviderID.displayName)") {
                        if prompt.storesChoice { setLookupProvider(AIService.shared.selectedProviderID) }
                        startLookup(prompt.kind, using: AIService.shared.selectedProviderID)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { prompt in
                if prompt.kind.isPhoto {
                    Text("\(lookupProviderID.displayName) is text-only and can't read photos. Use \(prompt.alternative.displayName) for this photo?")
                }
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
            VStack(alignment: .leading, spacing: 6) {
                Text(aiErrorMessage)
                    .foregroundStyle(.orange)
                if let failed = failedLookup, let retry = retryAlternative(for: failed) {
                    Button("Try again with \(retry.displayName)") {
                        startLookup(failed.kind, using: retry)
                    }
                }
            }
        } else if aiBusy {
            Text("Asking \((activeLookupProvider ?? lookupProviderID).displayName)…")
        } else {
            Text("Enter brand and model name, then hit return or the magnifying glass to look up the rest with \(lookupProviderID.displayName).")
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
        requestLookup(.brandModel)
    }

    /// Entry point for every AI lookup. The first time the on-device model
    /// is selected while a better-suited cloud provider is ready, the user
    /// picks one and that choice becomes the sticky lookup default — no
    /// prompting on later lookups. The Lookup Provider picker changes it
    /// any time. The app never switches providers on its own.
    private func requestLookup(_ kind: LookupKind) {
        let service = AIService.shared
        if service.identificationProviderID == nil,
           let alternative = service.identificationAlternative {
            providerPrompt = ProviderPrompt(kind: kind, alternative: alternative.id, storesChoice: true)
            return
        }
        // Photos can't run on the on-device model; offer a ready cloud
        // provider for this photo only, without touching the default.
        if kind.isPhoto, lookupProviderID == .foundationModels,
           let cloud = readyCloudProvider() {
            providerPrompt = ProviderPrompt(kind: kind, alternative: cloud, storesChoice: false)
            return
        }
        startLookup(kind, using: lookupProviderID)
    }

    private func setLookupProvider(_ id: AIProviderID) {
        lookupProviderID = id
        AIService.shared.identificationProviderID = id
    }

    private func readyCloudProvider() -> AIProviderID? {
        [AIProviderID.claude, .gemini].first { id in
            guard let provider = AIService.shared.provider(for: id) else { return false }
            return AIService.shared.readinessIssue(for: provider) == nil
        }
    }

    private func startLookup(_ kind: LookupKind, using providerID: AIProviderID) {
        Task { await runLookup(kind, using: providerID) }
    }

    private func runLookup(_ kind: LookupKind, using providerID: AIProviderID) async {
        aiErrorMessage = nil
        failedLookup = nil
        activeLookupProvider = providerID
        aiBusy = true
        defer {
            aiBusy = false
            activeLookupProvider = nil
        }
        do {
            let suggestion = try await perform(kind, using: providerID)
            if reviewEntries(for: suggestion).isEmpty, modelNumberChoices(for: suggestion).isEmpty {
                aiErrorMessage = "\(providerID.shortName) found no new details — fields already filled or nothing recognized."
            } else {
                pendingSuggestion = PendingSuggestion(suggestion: suggestion)
            }
        } catch let error as AIError {
            aiErrorMessage = error.errorDescription
            failedLookup = FailedLookup(kind: kind, provider: providerID)
        } catch {
            aiErrorMessage = "\(providerID.shortName): \(error.localizedDescription)"
            failedLookup = FailedLookup(kind: kind, provider: providerID)
        }
    }

    private func perform(_ kind: LookupKind, using providerID: AIProviderID) async throws -> ToolDetailsSuggestion {
        switch kind {
        case .brandModel:
            var suggestion = try await AIService.shared.lookupToolDetails(brand: brand, model: modelName, using: providerID)
            // Top up missing links when the form has none yet.
            if manufacturerLink.isEmpty, howToLink.isEmpty,
               suggestion.manufacturerLink == nil || suggestion.howToLink == nil,
               let links = try? await AIService.shared.suggestLinks(brand: brand, model: modelName, using: providerID) {
                suggestion.manufacturerLink = suggestion.manufacturerLink ?? links.manufacturerLink
                suggestion.howToLink = suggestion.howToLink ?? links.howToLinks?.first?.url
            }
            return suggestion
        case .barcode(let payload):
            return try await AIService.shared.lookupToolDetails(barcode: payload, using: providerID)
        case .packagingPhoto(let data):
            return try await AIService.shared.extractDetails(fromImage: data, using: providerID)
        }
    }

    /// Another ready provider to offer after a failure — cloud providers
    /// first; photo lookups skip the text-only on-device model.
    private func retryAlternative(for failed: FailedLookup) -> AIProviderID? {
        let order: [AIProviderID] = [.claude, .gemini, .foundationModels]
        return order.first { id in
            guard id != failed.provider else { return false }
            if failed.kind.isPhoto && id == .foundationModels { return false }
            guard let provider = AIService.shared.provider(for: id) else { return false }
            return AIService.shared.readinessIssue(for: provider) == nil
        }
    }

    private var autoFillSection: some View {
        Section {
            Picker("Lookup Provider", selection: Binding(
                get: { lookupProviderID },
                set: { setLookupProvider($0) }
            )) {
                ForEach(AIProviderID.allCases) { id in
                    Text(providerLabel(for: id)).tag(id)
                }
            }

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
            Text("Suggestions fill empty fields only; review before applying. Lookups use the provider above; other AI features use the one in AI Settings.")
        }
    }

    /// Picker labels carry the readiness issue so an unusable choice is
    /// visible before a lookup fails.
    private func providerLabel(for id: AIProviderID) -> String {
        guard let provider = AIService.shared.provider(for: id),
              let issue = AIService.shared.readinessIssue(for: provider) else {
            return id.displayName
        }
        return "\(id.displayName) — \(issue)"
    }

    private func extractFromPhoto(_ data: Data) {
        guard let downscaled = downscaledJPEG(from: data) else {
            aiErrorMessage = "Couldn't read the photo."
            return
        }
        requestLookup(.packagingPhoto(downscaled))
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

    /// Suggested values that would land in currently-empty fields. Competing
    /// model-number variants are excluded — they go through
    /// `modelNumberChoices` so the user picks exactly one.
    private func reviewEntries(for suggestion: ToolDetailsSuggestion) -> [SuggestionReviewView.Entry] {
        var entries: [SuggestionReviewView.Entry] = []
        func add(_ field: SuggestionField, _ label: String, _ value: String?, ifEmpty current: String) {
            if let value, !value.isEmpty, current.trimmingCharacters(in: .whitespaces).isEmpty {
                entries.append(.init(field: field, label: label, value: value))
            }
        }
        add(.brand, "Brand", suggestion.brand, ifEmpty: brand)
        add(.modelName, "Model Name", suggestion.modelName, ifEmpty: modelName)
        if modelNumberChoices(for: suggestion).isEmpty {
            add(.modelNumber, "Model Number", singleModelNumber(from: suggestion), ifEmpty: modelNumber)
        }
        if selectedType == nil, let path = suggestion.suggestedTypePath,
           matchType(forPath: path) != nil {
            entries.append(.init(field: .type, label: "Type", value: path))
        }
        if powerSource == nil, let source = suggestion.powerSource,
           PowerSource(rawValue: source) != nil {
            entries.append(.init(field: .powerSource, label: "Power Source", value: source))
        }
        if batteryVoltage == nil, let volts = suggestion.batteryVoltage {
            entries.append(.init(field: .voltage, label: "Voltage", value: "\(volts)V"))
        }
        if batteryAmpHours == nil, let ampHours = suggestion.batteryAmpHours {
            entries.append(.init(field: .ampHours, label: "Capacity", value: "\(ampHours.formatted())Ah"))
        }
        add(.manufacturerLink, "Manufacturer Link", suggestion.manufacturerLink, ifEmpty: manufacturerLink)
        add(.howToLink, "How-To Link", suggestion.howToLink, ifEmpty: howToLink)
        add(.notes, "Notes", suggestion.notes, ifEmpty: notes)
        return entries
    }

    /// Variant article numbers worth asking about: only when the field is
    /// still empty and the provider returned more than one distinct number.
    /// When the provider didn't flag a likely variant but its single
    /// `modelNumber` matches one option, that option inherits the default
    /// checkmark.
    private func modelNumberChoices(for suggestion: ToolDetailsSuggestion) -> [ModelNumberOption] {
        guard modelNumber.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        var seen = Set<String>()
        var options = (suggestion.modelNumberOptions ?? []).filter { option in
            guard let number = option.number, !number.isEmpty else { return false }
            return seen.insert(number).inserted
        }
        guard options.count > 1 else { return [] }
        if !options.contains(where: { $0.isLikely == true }),
           let single = suggestion.modelNumber,
           let index = options.firstIndex(where: { $0.number == single }) {
            options[index].isLikely = true
        }
        return options
    }

    /// The unambiguous model number, when there is one: the scalar answer,
    /// or the sole variant the provider listed.
    private func singleModelNumber(from suggestion: ToolDetailsSuggestion) -> String? {
        if let number = suggestion.modelNumber, !number.isEmpty { return number }
        let numbers = Set((suggestion.modelNumberOptions ?? []).compactMap(\.number).filter { !$0.isEmpty })
        return numbers.count == 1 ? numbers.first : nil
    }

    private func apply(_ suggestion: ToolDetailsSuggestion, fields: Set<SuggestionField>, chosenModelNumber: String?) {
        func fill(_ current: inout String, with value: String?, for field: SuggestionField) {
            guard fields.contains(field) else { return }
            if current.trimmingCharacters(in: .whitespaces).isEmpty, let value, !value.isEmpty {
                current = value
            }
        }
        fill(&brand, with: suggestion.brand, for: .brand)
        fill(&modelName, with: suggestion.modelName, for: .modelName)
        fill(&modelNumber, with: singleModelNumber(from: suggestion), for: .modelNumber)
        if let chosenModelNumber, !chosenModelNumber.isEmpty,
           modelNumber.trimmingCharacters(in: .whitespaces).isEmpty {
            modelNumber = chosenModelNumber
        }
        // The applied article number's variant description doubles as the
        // kit/combo the tool came in.
        if kit.trimmingCharacters(in: .whitespaces).isEmpty,
           let detail = (suggestion.modelNumberOptions ?? [])
               .first(where: { $0.number == modelNumber })?.detail,
           !detail.isEmpty {
            kit = detail
        }
        if fields.contains(.type), selectedType == nil, let path = suggestion.suggestedTypePath {
            selectedType = matchType(forPath: path)
        }
        if fields.contains(.powerSource), powerSource == nil, let source = suggestion.powerSource {
            powerSource = PowerSource(rawValue: source)
        }
        if fields.contains(.voltage), batteryVoltage == nil { batteryVoltage = suggestion.batteryVoltage }
        if fields.contains(.ampHours), batteryAmpHours == nil { batteryAmpHours = suggestion.batteryAmpHours }
        fill(&manufacturerLink, with: suggestion.manufacturerLink, for: .manufacturerLink)
        fill(&howToLink, with: suggestion.howToLink, for: .howToLink)
        fill(&notes, with: suggestion.notes, for: .notes)
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
        target.kit = kit
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
