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
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemGray4))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary)
                            .frame(width: geo.size.width * CGFloat(max(0, min(1, progress))))
                    }
                }
                .frame(height: 4)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
                    .monospacedDigit()
            }

            HStack {
                Spacer()
                Button(action: onTocTap) {
                    Image(systemName: "list.bullet")
                        .frame(width: 44, height: 44)
                }
                Spacer()
                Button(action: onBookmarkTap) {
                    Image(systemName: "bookmark")
                        .frame(width: 44, height: 44)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                        onBookmarkLongPress()
                    }
                )
                Spacer()
                Button(action: onSettingsTap) {
                    Image(systemName: "textformat.size")
                        .frame(width: 44, height: 44)
                }
                Spacer()
            }
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
}
