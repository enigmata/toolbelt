import Foundation
import SwiftData

@Model
final class ToolPhoto {
    @Attribute(.externalStorage) var data: Data = Data()
    var createdAt: Date = Date.now
    var tool: Tool?

    init(data: Data) {
        self.data = data
    }
}
