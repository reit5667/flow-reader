import SwiftUI

struct ReaderControlsView: View {
    let book: Book
    let progress: Float
    let onTocTap: () -> Void
    let onBookmarkTap: () -> Void
    let onBookmarkLongPress: () -> Void
    let onSettingsTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            controlSheet
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var controlSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Drag handle
            HStack {
                Spacer()
                RoundedRectangle(cornerRadius: 2)
                    .fill(DS.Color.separator)
                    .frame(width: 36, height: 4)
                Spacer()
            }
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                Text(book.author.isEmpty ? "Неизвестный автор" : book.author)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.textTertiary)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.Color.separator)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.Color.accent)
                            .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))))
                    }
                }
                .frame(height: 3)

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.textTertiary)
                    .frame(width: 36, alignment: .trailing)
                    .monospacedDigit()
            }

            HStack {
                Spacer()
                Button(action: onTocTap) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                Button(action: onBookmarkTap) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        onBookmarkLongPress()
                    }
                )
                Spacer()
                Button(action: onSettingsTap) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(DS.Color.surface)
    }
}
