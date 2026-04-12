import SwiftUI
import CoralCore

/// Tappable 1–5 star rating. Tap active star again to clear.
struct RatingView: View {
    let rating: Int
    let onRate: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(.system(size: 14))
                    .foregroundStyle(star <= rating ? JM.star : JM.textMuted)
                    .onTapGesture {
                        onRate(star == rating ? 0 : star)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating: \(rating) stars")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onRate(min(rating + 1, 5))
            case .decrement: onRate(max(rating - 1, 0))
            @unknown default: break
            }
        }
    }
}
