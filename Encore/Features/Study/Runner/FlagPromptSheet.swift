import EncoreKit
import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "com.amierlorenz.Encore", category: "flag")

/// Sheet for submitting a flag against a card with reason, note, and optional suggested fix.
struct FlagPromptSheet: View {
    let prompt: Prompt
    var concept: Concept?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var reason: FlagReason = .wrong
    @State private var note: String = ""
    @State private var suggestedFix: String = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reason", selection: $reason) {
                        ForEach(FlagReason.allCases, id: \.self) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }
                } header: {
                    Text("Why is this card wrong?")
                }

                Section {
                    TextField("What's incorrect or confusing?", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Note (optional)")
                }

                Section {
                    TextField("Correct answer, explanation, or wording", text: $suggestedFix, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Suggested Fix (optional)")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Flag Card")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Flag Card") {
                        submitFlag()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 320)
        #endif
    }

    private func submitFlag() {
        let exporter = FlagExporter()
        do {
            try exporter.exportFlag(
                for: prompt,
                concept: concept,
                reason: reason,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                suggestedFix: suggestedFix.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            prompt.isFlagged = true
            modelContext.saveLogging()
            dismiss()
        } catch {
            logger.error("Failed to export flag: \(error)")
            errorMessage = "Failed to save flag: \(error.localizedDescription)"
        }
    }
}
