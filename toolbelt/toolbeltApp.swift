import SwiftUI
import SwiftData

@main
struct ToolbeltApp: App {
    let container: ModelContainer

    init() {
        let schema = Schema([Tool.self, ToolType.self, ToolPhoto.self])
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let inMemory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [inMemory])
            SeedData.seedIfNeeded(context: container.mainContext)
            return
        }
        do {
            let cloud = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private("iCloud.com.enigmata.toolbelt")
            )
            container = try ModelContainer(for: schema, configurations: [cloud])
        } catch {
            // CloudKit needs signed entitlements and an iCloud account; CLI
            // builds (CODE_SIGNING_ALLOWED=NO) and signed-out devices fall
            // back to the same on-disk store without sync.
            do {
                let local = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
                container = try ModelContainer(for: schema, configurations: [local])
            } catch {
                fatalError("Failed to create model container: \(error)")
            }
        }
        SeedData.seedIfNeeded(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
