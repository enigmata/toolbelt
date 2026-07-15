import Foundation
import SwiftData

enum Disposition: String, Codable, CaseIterable, Identifiable {
    case inUse = "In Use"
    case sold = "Sold"
    case retired = "Retired"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .inUse: "checkmark.circle"
        case .sold: "dollarsign.circle"
        case .retired: "archivebox"
        }
    }
}

enum PowerSource: String, Codable, CaseIterable, Identifiable {
    case corded = "Corded"
    case battery = "Battery"

    var id: String { rawValue }
}

/// All properties are optional or defaulted to stay CloudKit-compatible.
@Model
final class Tool {
    var name: String = ""
    var brand: String = ""
    /// Marketed model designation, e.g. "XDT17" or "OSC 18". With brand,
    /// this identifies the tool.
    var modelName: String = ""
    /// Manufacturer article/part number, e.g. "10041861". Desired but often
    /// not known at entry time.
    var modelNumber: String = ""
    var serialNumber: String = ""
    var type: ToolType?
    var dispositionRaw: String = Disposition.inUse.rawValue
    var powerSourceRaw: String?
    var batteryVoltage: Int?
    var batteryAmpHours: Double?
    var storageLocation: String = ""
    var purchaseDate: Date?
    var purchaseStore: String = ""
    var manufacturerLink: String = ""
    var howToLink: String = ""
    var notes: String = ""
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \ToolPhoto.tool)
    var photos: [ToolPhoto]? = []

    init(name: String = "", type: ToolType? = nil) {
        self.name = name
        self.type = type
    }

    var disposition: Disposition {
        get { Disposition(rawValue: dispositionRaw) ?? .inUse }
        set { dispositionRaw = newValue.rawValue }
    }

    var powerSource: PowerSource? {
        get { powerSourceRaw.flatMap(PowerSource.init(rawValue:)) }
        set { powerSourceRaw = newValue?.rawValue }
    }

    var kind: ToolKind? {
        type?.kind
    }

    /// Title shown across the UI. Tools are identified by brand + model name;
    /// `name` is a legacy field kept for records created before it was
    /// dropped from the form, and wins when present. Model number stands in
    /// for records predating the model name/number split.
    var displayName: String {
        if !name.isEmpty { return name }
        let model = modelName.isEmpty ? modelNumber : modelName
        let brandModel = [brand, model]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !brandModel.isEmpty { return brandModel }
        return type?.name ?? "Untitled Tool"
    }

    /// e.g. "18V 5.0Ah" for battery tools.
    var batteryLabel: String? {
        guard powerSource == .battery else { return nil }
        var parts: [String] = []
        if let batteryVoltage { parts.append("\(batteryVoltage)V") }
        if let batteryAmpHours { parts.append("\(batteryAmpHours.formatted())Ah") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// e.g. "3 years, 2 months" since purchase.
    var ageDescription: String? {
        guard let purchaseDate else { return nil }
        let components = Calendar.current.dateComponents([.year, .month], from: purchaseDate, to: .now)
        let years = components.year ?? 0
        let months = components.month ?? 0
        var parts: [String] = []
        if years > 0 { parts.append("\(years) year\(years == 1 ? "" : "s")") }
        if months > 0 { parts.append("\(months) month\(months == 1 ? "" : "s")") }
        return parts.isEmpty ? "Less than a month" : parts.joined(separator: ", ")
    }

    /// True if any searchable attribute contains the query.
    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let haystack = [
            name, brand, modelName, modelNumber, serialNumber,
            storageLocation, purchaseStore, notes,
            type?.path ?? "", disposition.rawValue,
            powerSource?.rawValue ?? "", batteryLabel ?? "",
        ].joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(query)
    }
}
