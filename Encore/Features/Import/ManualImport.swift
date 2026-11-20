#if os(macOS)
import AppKit
import EncoreKit
import OSLog
import SwiftData
import UniformTypeIdentifiers

@MainActor
func openImportPanel(context: ModelContext) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.title = "Import File"
    panel.prompt = "Import"
    if panel.runModal() == .OK, let url = panel.url {
        do {
            let importer = Importer(context: context)
            let plan = try importer.importFile(at: url)
            Logger.app.info("Manual import applied: \(plan.concepts.new) new concepts, \(plan.concepts.updated) updated.")
        } catch {
            Logger.app.error("Manual import failed: \(error)")
        }
    }
}
#endif
