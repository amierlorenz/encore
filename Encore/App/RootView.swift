import EncoreKit
import OSLog
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(VariantGenerationService.self) private var variantGeneration
    @AppStorage(SettingsKey.aiModel) private var aiModel = FoundationModelsProvider.ModelChoice.onDevice.rawValue
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        root
            .task(prepareStore)
    }

    private var root: some View {
        TabView(selection: tabSelection) {
            ForEach(SidebarSection.tabs) { section in
                Tab(section.title, systemImage: section.systemImage, value: section) {
                    SectionDetailView(section: section)
                }
            }
        }
        .tabViewStyle(.tabBarOnly)
    }

    private var tabSelection: Binding<SidebarSection> {
        Binding { navigation.selection ?? .dashboard } set: { navigation.selection = $0 }
    }

    private func prepareStore() async {
        #if DEBUG
        DebugLaunchOptions.apply(context: modelContext, navigation: navigation)
        #endif
        do {
            try DuplicateMerger.mergeAll(in: modelContext)
        } catch {
            Logger.app.error("Duplicate merge failed: \(error)")
        }
        variantGeneration.start(context: modelContext, provider: FoundationModelsProvider(storedChoice: aiModel))
    }
}

#Preview {
    RootView()
        .environment(VariantGenerationService())
        .environment(AppNavigation())
        .environment(SyncStatusService())
        .modelContainer(try! ModelContainerFactory.make(storage: .inMemory))
}
