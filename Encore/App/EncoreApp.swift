import EncoreKit
import OSLog
import SwiftData
import SwiftUI

@main
struct EncoreApp: App {
    private let container: ModelContainer
    @State private var variantGeneration = VariantGenerationService()
    @State private var navigation = AppNavigation()
    @State private var syncStatus = SyncStatusService()
    @State private var settingsSync = SettingsSync()
    #if os(macOS)
    @State private var handoffWatcher: HandoffWatcher?
    #endif

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(variantGeneration)
                .environment(navigation)
                .environment(syncStatus)
                .task {
                    syncStatus.start()
                    #if DEBUG
                    if DebugLaunchOptions.usesLocalStore { return }
                    #endif
                    settingsSync.start()
                    #if os(macOS)
                    if handoffWatcher == nil {
                        let watcher = HandoffWatcher(context: container.mainContext)
                        handoffWatcher = watcher
                        watcher.start()
                    }
                    #endif
                }
        }
        .modelContainer(container)
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .importExport) {
                Button("Import file…") {
                    openImportPanel(context: container.mainContext)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
        #endif
    }

    private static func makeContainer() -> ModelContainer {
        #if DEBUG
        if DebugLaunchOptions.usesLocalStore, let container = try? ModelContainerFactory.make(storage: .local) {
            return container
        }
        #endif
        do {
            return try ModelContainerFactory.make(storage: .cloudSynced)
        } catch {
            Logger.app.error("CloudKit container failed, falling back to local store: \(error)")
        }
        do {
            return try ModelContainerFactory.make(storage: .local)
        } catch {
            fatalError("Unable to create model container: \(error)")
        }
    }
}
