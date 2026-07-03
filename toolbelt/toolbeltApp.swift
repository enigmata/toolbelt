import SwiftUI
import SwiftData

@main
struct ToolbeltApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Tool.self, ToolType.self, ToolPhoto.self)
            SeedData.seedIfNeeded(context: container.mainContext)
        } catch {
            fatalError("Failed to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
