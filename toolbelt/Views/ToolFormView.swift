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

    @State private var name: String
    @State private var brand: String
    @State private var modelNumber: String
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

    init(tool: Tool? = nil) {
        self.tool = tool
        _name = State(initialValue: tool?.name ?? "")
        _brand = State(initialValue: tool?.brand ?? "")
        _modelNumber = State(initialValue: tool?.modelNumber ?? "")
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

    private var sortedTypes: [ToolType] {
        allTypes.sorted {
            ($0.kind.rawValue, $0.path) < ($1.kind.rawValue, $1.path)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Brand", text: $brand)
                    TextField("Model Number", text: $modelNumber)
                    Picker("Type", selection: $selectedType) {
                        Text("None").tag(ToolType?.none)
                        ForEach(sortedTypes) { type in
                            Text("\(type.kind.rawValue) › \(type.path)")
                                .tag(Optional(type))
                        }
                    }
                }

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
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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
        }
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
        target.name = name
        target.brand = brand
        target.modelNumber = modelNumber
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
