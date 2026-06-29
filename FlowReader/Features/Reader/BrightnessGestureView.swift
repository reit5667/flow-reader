import SwiftUI

struct BrightnessGestureView: View {
    let brightness: CGFloat

    var body: some View {
        VStack {
            Spacer()
            BrightnessIndicatorView(brightness: brightness)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
    }
}

struct BrightnessIndicatorView: View {
    let brightness: CGFloat

    private let barHeight: CGFloat = 80

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: brightness > 0.5 ? "sun.max.fill" : "sun.min")
                .font(.system(size: 14, weight: .medium))

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 4, height: barHeight)

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 4, height: max(4, barHeight * brightness))
                    .animation(.linear(duration: 0.05), value: brightness)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.black.opacity(0.55))
        )
        .padding(.leading, 8)
    }
}
