import EncoreKit
import SwiftUI

struct ExamRow: View {
    let exam: Exam

    var body: some View {
        VStack(alignment: .leading) {
            Text(exam.name)
            Text("\(exam.course?.displayName ?? "No class") · \(exam.date.formatted(date: .abbreviated, time: .shortened)) · \((exam.units ?? []).count) units")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
