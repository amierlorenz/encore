import EncoreKit
import SwiftData
import SwiftUI

/// Marks a bad or confusing prompt so sessions stop showing it.
struct FlagPromptButton: View {
    let prompt: Prompt
    var concept: Concept? = nil

    @State private var isShowingSheet = false

    var body: some View {
        if prompt.isFlagged {
            Label("Flagged. It won't be shown again; review it in the Library.", systemImage: "flag.fill")
                .foregroundStyle(.orange)
        } else {
            Button("Flag this prompt", systemImage: "flag") {
                isShowingSheet = true
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("This card is wrong")
            .sheet(isPresented: $isShowingSheet) {
                FlagPromptSheet(prompt: prompt, concept: concept)
            }
        }
    }
}
