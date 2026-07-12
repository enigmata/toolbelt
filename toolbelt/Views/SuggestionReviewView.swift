import SwiftUI

/// Shows what an AI lookup would fill in (empty fields only) before it
/// touches the form.
struct SuggestionReviewView: View {
    let entries: [(label: String, value: String)]
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(entries, id: \.label) { entry in
                        LabeledContent(entry.label, value: entry.value)
                    }
                } footer: {
                    Text("Only empty fields are filled; existing values are never overwritten.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Suggested Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply", action: onApply)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
