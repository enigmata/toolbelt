import SwiftUI

/// Form fields an AI suggestion can fill, used to report which rows the
/// user accepted in the review sheet.
enum SuggestionField: Hashable {
    case brand, modelName, modelNumber, type, powerSource, voltage, ampHours
    case manufacturerLink, howToLink, notes
}

/// Shows what an AI lookup would fill in (empty fields only) before it
/// touches the form. Every value has a checkbox so the user can reject
/// individual suggestions; competing model-number variants are a separate
/// pick-one list.
struct SuggestionReviewView: View {
    struct Entry: Identifiable {
        let field: SuggestionField
        let label: String
        let value: String
        var id: SuggestionField { field }
    }

    let entries: [Entry]
    /// Competing article numbers for different kits/configurations of the
    /// same model; the user checks at most one.
    let modelNumberOptions: [ModelNumberOption]
    let onApply: (_ fields: Set<SuggestionField>, _ modelNumber: String?) -> Void
    let onCancel: () -> Void

    @State private var checkedFields: Set<SuggestionField>
    @State private var chosenModelNumber: String?

    init(
        entries: [Entry],
        modelNumberOptions: [ModelNumberOption] = [],
        onApply: @escaping (_ fields: Set<SuggestionField>, _ modelNumber: String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.entries = entries
        self.modelNumberOptions = modelNumberOptions
        self.onApply = onApply
        self.onCancel = onCancel
        // Providers are instructed to leave uncertain fields empty, so
        // plain suggestions start checked. A variant number starts checked
        // only when the provider singled one out as likely — otherwise
        // only the user knows which kit they own.
        _checkedFields = State(initialValue: Set(entries.map(\.field)))
        let likely = modelNumberOptions.filter { $0.isLikely == true }
        _chosenModelNumber = State(initialValue: likely.count == 1 ? likely.first?.number : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if !entries.isEmpty {
                    Section {
                        ForEach(entries) { entry in
                            checkRow(
                                isChecked: checkedFields.contains(entry.field),
                                label: entry.label,
                                value: entry.value
                            ) {
                                if !checkedFields.insert(entry.field).inserted {
                                    checkedFields.remove(entry.field)
                                }
                            }
                        }
                    } footer: {
                        Text("Checked values fill empty fields only; existing values are never overwritten.")
                    }
                }

                if !modelNumberOptions.isEmpty {
                    Section {
                        ForEach(modelNumberOptions, id: \.number) { option in
                            checkRow(
                                isChecked: chosenModelNumber == option.number,
                                label: option.number ?? "",
                                value: option.detail ?? ""
                            ) {
                                chosenModelNumber = chosenModelNumber == option.number ? nil : option.number
                            }
                        }
                    } header: {
                        Text("Model Number")
                    } footer: {
                        Text("This model is sold in several configurations — check the one you own. Its description also fills the Kit / Combo field.")
                    }
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
                    Button("Apply") { onApply(checkedFields, chosenModelNumber) }
                        .disabled(checkedFields.isEmpty && chosenModelNumber == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func checkRow(
        isChecked: Bool, label: String, value: String, onToggle: @escaping () -> Void
    ) -> some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .foregroundStyle(.primary)
                    if !value.isEmpty {
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
    }
}
