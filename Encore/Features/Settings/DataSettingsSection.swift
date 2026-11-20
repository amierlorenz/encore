import EncoreKit
import OSLog
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct DataSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var isConfirming = false
    @State private var status: String?
    @State private var export: JSONFileDocument?

    var body: some View {
        Section {
            Button("Export Backup…", systemImage: "square.and.arrow.up", action: prepareExport)
            Button("Delete All Data", systemImage: "trash", role: .destructive) { isConfirming = true }
                .foregroundStyle(.red)
                .confirmationDialog("Delete all study data?", isPresented: $isConfirming, titleVisibility: .visible) {
                    Button("Delete Everything", role: .destructive, action: deleteAll)
                } message: {
                    Text("Removes every class, concept, prompt, exam, review, and preset on all your devices through iCloud. Export a backup first if you might want it back. This can't be undone.")
                }
            if let status {
                Text(status)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Settings are kept.")
        }
        .fileExporter(isPresented: isExporting, document: export, contentType: .json, defaultFilename: exportFilename) { _ in
            export = nil
        }
    }

    private var isExporting: Binding<Bool> {
        Binding { export != nil } set: { if !$0 { export = nil } }
    }

    private var exportFilename: String {
        "Encore \(Date.now.formatted(.iso8601.year().month().day())).json"
    }

    private func prepareExport() {
        do {
            export = JSONFileDocument(data: try Exporter(context: modelContext).document().encoded())
        } catch {
            Logger.app.error("Export failed: \(error)")
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private func deleteAll() {
        do {
            try DataReset.deleteAll(in: modelContext)
            status = "All study data deleted."
        } catch {
            Logger.app.error("Delete all failed: \(error)")
            status = "Couldn't delete everything: \(error.localizedDescription)"
        }
    }
}
