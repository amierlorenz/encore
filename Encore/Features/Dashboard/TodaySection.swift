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
                                Label("Today's Session", systemImage: "play.circle.fill")
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
