import SwiftUI

/// 展開後的暫存架分頁。
struct ShelfPanelView: View {
    let island: IslandViewModel

    private var shelf: ShelfModel { island.shelf }

    var body: some View {
        Group {
            if island.isFileDragHovering {
                HStack(spacing: 12) {
                    DropZone(title: "放到暫存架", symbol: "tray.and.arrow.down.fill", tint: .white) { urls in
                        shelf.add(urls) > 0
                    }
                    DropZone(title: "AirDrop", symbol: "dot.radiowaves.left.and.right", tint: .blue) { urls in
                        shelf.airDrop(urls)
                    }
                }
            } else if shelf.items.isEmpty {
                EmptyShelfView()
            } else {
                HStack(spacing: 14) {
                    HorizontalScroll {
                        HStack(spacing: 6) {
                            ForEach(shelf.items.reversed()) { item in
                                ShelfTile(item: item, thumbnail: shelf.thumbnails[item.url], island: island)
                            }
                        }
                    }
                    VStack(spacing: 8) {
                        PillButton(title: "全部 AirDrop", isSelected: false) {
                            shelf.airDrop(shelf.items.map(\.url))
                        }
                        PillButton(title: "清空", isSelected: false) {
                            withAnimation(.smooth(duration: 0.2)) { shelf.removeAll() }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
    }
}

private struct EmptyShelfView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            Text("把檔案拖到瀏海就能暫放")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("拖進來時也可以放到 AirDrop 直接傳送")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

/// 拖曳檔案經過時顯示的投放區。
private struct DropZone: View {
    let title: String
    let symbol: String
    let tint: Color
    let onDrop: ([URL]) -> Bool

    @ViewState private var isTargeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .symbolEffect(.bounce, value: isTargeted)
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(isTargeted ? tint : .white.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(isTargeted ? 0.18 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(isTargeted ? tint : .white.opacity(0.25))
        )
        .scaleEffect(isTargeted ? 1.02 : 1)
        .animation(.smooth(duration: 0.2), value: isTargeted)
        .fileDropDestination(perform: onDrop) { targeted in
            isTargeted = targeted
        }
    }
}

private struct ShelfTile: View {
    let item: ShelfModel.Item
    let thumbnail: NSImage?
    let island: IslandViewModel

    @ViewState private var isHovering = false

    var body: some View {
        VStack(spacing: 5) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 46, height: 46)
            Text(item.name)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 70)
        }
        .padding(6)
        .frame(width: 82, height: 96)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.1 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { island.shelf.open(item) }
        .onDrag {
            island.beginShelfDragOut()
            return NSItemProvider(object: item.url as NSURL)
        }
        .contextMenu {
            Button("開啟") { island.shelf.open(item) }
            Button("在 Finder 中顯示") { island.shelf.revealInFinder(item) }
            Button("用 AirDrop 傳送") { island.shelf.airDrop([item.url]) }
            Divider()
            Button("從暫存架移除") {
                withAnimation(.smooth(duration: 0.2)) { island.shelf.remove(item) }
            }
        }
        .help(item.name)
    }
}
