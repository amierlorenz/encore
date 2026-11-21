import SwiftUI

/// A Liquid Glass banner shown on iPhone and Mac when Articulate's daily plan
/// has not run for more than 30 hours.
struct StalePlanBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 640)
        .glassEffect(.regular.tint(.orange.opacity(0.12)), in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
