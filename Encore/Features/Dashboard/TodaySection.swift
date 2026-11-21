import EncoreKit
import SwiftUI

/// Today's numbers as glass cards, with the main actions below. Placed in the
/// section header so it sits outside the form's grouped container.
struct TodaySection: View {
    let due: Int
    let newRemaining: Int
    let reviewedToday: Int
    var plan: DailyPlan? = nil
    var isPlanDone: Bool = false
    var staleMessage: String? = nil
    let onReview: () -> Void
    let onLearn: () -> Void
    var onStartPlan: (() -> Void)? = nil
    var onKeepPracticing: (() -> Void)? = nil
    var onStartPracticeTest: (() -> Void)? = nil
    var onStartReviewQuiz: (() -> Void)? = nil

    private var planButtonTitle: String {
        if let focus = plan?.examFocus.first {
            return "Today's Session · Ramp Day \(focus.rampDay)"
        }
        return "Today's Session"
    }

    var body: some View {
        Section {
        } header: {
            VStack(spacing: 18) {
                if let staleMessage {
                    StalePlanBanner(message: staleMessage)
                }
                SectionTitle(title: "Today")
                HStack(spacing: 12) {
                    StatCard(value: due, title: "Due for review", systemImage: "arrow.counterclockwise", tint: due > 0 ? .orange : nil)
                    StatCard(value: newRemaining, title: "New left today", systemImage: "sparkles", tint: nil)
                    StatCard(value: reviewedToday, title: "Answered today", systemImage: "checkmark.circle", tint: reviewedToday > 0 ? .green : nil)
                }
                .frame(maxWidth: 640)
                HStack(spacing: 12) {
                    if let plan, !plan.isExpired() {
                        if !plan.isAvailable() {
                            Button(action: {}) {
                                Label("Ready at 6:00 AM", systemImage: "clock")
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.glass)
                            .disabled(true)
                        } else if isPlanDone {
                            Button(action: { onKeepPracticing?() }) {
                                Label("Keep Practicing", systemImage: "sparkles")
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.glassProminent)
                        } else {
                            Button(action: { onStartPlan?() }) {
                                Label(planButtonTitle, systemImage: "play.circle.fill")
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.glassProminent)
                        }
                    } else {
                        Button(action: onReview) {
                            Label("Review Due", systemImage: "arrow.counterclockwise")
                                .font(.headline)
                                .lineLimit(1)
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(due == 0)
                        Button(action: onLearn) {
                            Label("Learn New", systemImage: "sparkles")
                                .font(.headline)
                                .lineLimit(1)
                        }
                        .buttonStyle(.glass)
                        .disabled(newRemaining == 0)
                    }
                }
                .labelStyle(.titleAndIcon)
                .controlSize(.large)
                if let plan, !plan.isExpired(), plan.isAvailable(), plan.practiceTest != nil || plan.reviewQuiz != nil {
                    HStack(spacing: 12) {
                        if plan.practiceTest != nil {
                            Button(action: { onStartPracticeTest?() }) {
                                Label("Practice Test", systemImage: "pencil.and.list.clipboard")
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.glass)
                        }
                        if plan.reviewQuiz != nil {
                            Button(action: { onStartReviewQuiz?() }) {
                                Label("Review Quiz", systemImage: "checklist")
                                    .font(.headline)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .controlSize(.regular)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .textCase(nil)
            .foregroundStyle(.primary)
        }
    }
}

private struct StatCard: View {
    let value: Int
    let title: String
    let systemImage: String
    let tint: Color?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint ?? .secondary)
            Text("\(value)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .padding(10)
        .glassEffect(tint.map { .regular.tint($0.opacity(0.12)) } ?? .regular, in: .rect(cornerRadius: 20))
        .animation(.spring(duration: 0.4), value: value)
        .accessibilityElement(children: .combine)
    }
}
