import SwiftUI
import SwiftData
import PhotosUI

/// Photograph a tool at hand and jump to its detail page — matches against
/// the photos already in the inventory, entirely on-device.
struct IdentifyToolView: View {
    @Query private var tools: [Tool]

    @State private var showingCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var matches: [PhotoMatchService.Match]?
    @State private var busy = false
    @State private var errorMessage: String?

    private var toolsWithPhotos: [Tool] {
        tools.filter { !($0.photos ?? []).isEmpty }
    }

    var body: some View {
        List {
            Section {
                Button {
                    showingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera.viewfinder")
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
                if busy {
                    HStack {
                        ProgressView()
                        Text("Comparing against \(toolsWithPhotos.count) tools…")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Identify a Tool")
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.orange)
                } else if toolsWithPhotos.isEmpty {
                    Text("Add photos to your tools first — matching compares against stored photos, entirely on this device.")
                } else {
                    Text("Photograph the tool at hand; matching happens on this device.")
                }
            }

            if let matches {
                Section("Matches") {
                    if matches.isEmpty {
                        Text("No similar tools found.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(matches) { match in
                        NavigationLink(value: match.tool) {
                            HStack {
                                if let data = (match.tool.photos ?? []).first?.data {
                                    PhotoImage(data: data)
                                        .frame(width: 44, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                VStack(alignment: .leading) {
                                    Text(match.tool.displayName)
                                        .font(.headline)
                                    Text(match.confidence)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Identify")
        .navigationDestination(for: Tool.self) { tool in
            ToolDetailView(tool: tool)
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraCaptureView { data in
                Task { await identify(data) }
            }
        }
        .task(id: pickerItem) {
            guard let pickerItem else { return }
            if let data = try? await pickerItem.loadTransferable(type: Data.self) {
                await identify(data)
            }
            self.pickerItem = nil
        }
    }

    private func identify(_ imageData: Data) async {
        errorMessage = nil
        matches = nil
        busy = true
        defer { busy = false }
        do {
            matches = try await PhotoMatchService.shared.rankTools(matching: imageData, in: toolsWithPhotos)
        } catch {
            errorMessage = "Couldn't analyze the photo: \(error.localizedDescription)"
        }
    }
}
