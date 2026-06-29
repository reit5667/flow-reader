import SwiftUI

struct TOCItem: Identifiable {
    var id: Int { index }
    let index: Int
    let title: String
}

struct TOCView: View {
    let items: [TOCItem]
    let currentProgress: Float
    let onSelect: (TOCItem) -> Void

    @Environment(\.dismiss) private var dismiss

    private var currentChapterIndex: Int {
        guard !items.isEmpty else { return 0 }
        return min(Int(currentProgress * Float(items.count)), items.count - 1)
    }

    var body: some View {
        NavigationStack {
            List(items) { item in
                Button {
                    onSelect(item)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        if item.index == currentChapterIndex {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        } else {
                            Color.clear.frame(width: 10, height: 10)
                        }
                        Text(item.title)
                            .foregroundStyle(item.index == currentChapterIndex ? Color.accentColor : Color.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("Оглавление недоступно", systemImage: "list.bullet")
                }
            }
            .navigationTitle("Оглавление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
