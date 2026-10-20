import SwiftUI

/// 展開後的剪貼簿分頁：左邊是可以上下轉的滾輪，右邊是選到那筆的預覽。
struct ClipboardPanelView: View {
    let island: IslandViewModel

    private var clipboard: ClipboardModel { island.clipboard }

    var body: some View {
        Group {
            if clipboard.items.isEmpty {
                EmptyClipboardView()
            } else {
                HStack(spacing: 14) {
                    ClipboardWheel(island: island)
                        .frame(width: 210)
                    if let item = island.selectedClipboardItem {
                        ClipboardPreview(item: item, clipboard: clipboard)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onChange(of: clipboard.items.map(\.id)) { island.clipboardItemsChanged() }
    }
}

// MARK: - 滾輪

/// 像計時器轉盤的清單：中間那列是選到的，上下的列沿著圓柱往後轉、變小變淡。
private struct ClipboardWheel: View {
    let island: IslandViewModel

    var body: some View {
        let items = island.clipboard.items
        let position = island.clipboardWheel.position
        let selected = island.clipboardWheel.index(count: items.count)

        ZStack {
            // 選取帶
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.1))
                .frame(height: WheelTracker.rowHeight)
                .overlay(alignment: .trailing) {
                    Text("\(selected + 1)/\(items.count)")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.trailing, 8)
                }
            // 離中間 3 列以外的已經完全透明（見 WheelRowEffect），不用畫；紀錄可能有上百筆
            let visible = items.enumerated().filter { abs(CGFloat($0.offset) - position) < 4.5 }
            ForEach(visible, id: \.element.id) { index, item in
                WheelRow(item: item, clipboard: island.clipboard, isSelected: index == selected)
                    .padding(.trailing, 34)
                    .frame(height: WheelTracker.rowHeight)
                    .modifier(WheelRowEffect(distance: CGFloat(index) - position))
                    .onTapGesture {
                        if index == selected {
                            island.clipboard.copy(item)
                        } else {
                            island.selectClipboardItem(at: index)
                        }
                    }
                    .contextMenu { ClipboardItemMenu(item: item, clipboard: island.clipboard) }
            }
        }
        .frame(maxHeight: .infinity)
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .contentShape(Rectangle())
        .help(tr("上下滑動選擇，點中間那筆複製", "Scroll to choose; click the middle item to copy"))
    }
}

/// 滾輪上每一列的位置：放在一個很平的圓柱上，離中間越遠稍微往後轉、變小變淡；
/// 上下各 2 列都還看得清楚，第 3 列才轉出去。
/// 做成 Animatable，對齊動畫時每一格都沿著圓柱走，而不是直線移動。
private struct WheelRowEffect: ViewModifier, Animatable {
    var distance: CGFloat

    var animatableData: CGFloat {
        get { distance }
        set { distance = newValue }
    }

    /// 相鄰兩列在圓柱上差幾度（弧度）。
    private static let step: CGFloat = 0.22
    /// 圓柱半徑：讓中間兩列剛好差一列高。
    private static let radius = WheelTracker.rowHeight / sin(step)

    func body(content: Content) -> some View {
        let angle = min(max(distance * Self.step, -.pi / 2), .pi / 2)
        let far = min(abs(distance), 3.5)
        content
            .scaleEffect(1 - far * 0.03)
            .rotation3DEffect(.radians(-Double(angle)), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .offset(y: sin(angle) * Self.radius)
            // 第 1、2 列 0.85、0.7，第 3 列以後很快消失
            .opacity(far <= 2 ? 1 - far * 0.15 : max(0, 0.7 - (far - 2) * 0.7))
            .allowsHitTesting(abs(distance) < 2.6)
    }
}

private struct WheelRow: View {
    let item: ClipboardModel.Item
    let clipboard: ClipboardModel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            ClipboardItemIcon(item: item, clipboard: clipboard, size: 16)
            Text(item.wheelTitle)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(.white.opacity(isSelected ? 1 : 0.8))
                .lineLimit(1)
                .truncationMode(.tail)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel(tr("已釘選", "Pinned"))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .contentShape(Rectangle())
    }
}

/// 列上的小圖示：圖片用縮圖、檔案用檔案圖示，其他用類型符號。
private struct ClipboardItemIcon: View {
    let item: ClipboardModel.Item
    let clipboard: ClipboardModel
    let size: CGFloat

    var body: some View {
        Group {
            switch item.preview {
            case .image(let image):
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            case .files(let urls):
                Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path).bitmapCopy(pointSize: 32) ?? NSImage())
                    .resizable()
                    .frame(width: size, height: size)
            case .link:
                Image(systemName: "link")
                    .font(.system(size: size * 0.7, weight: .semibold))
                    .foregroundStyle(.blue)
            case .text:
                Image(systemName: "text.alignleft")
                    .font(.system(size: size * 0.7, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 預覽

private struct ClipboardPreview: View {
    let item: ClipboardModel.Item
    let clipboard: ClipboardModel

    @ViewState private var isHovering = false

    private var isCopied: Bool { clipboard.recentlyCopiedID == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 換選取時只有內容換掉、淡入淡出；疊在 ZStack 裡，新舊交接時不會擠動下面的按鈕列
            ZStack(alignment: .topLeading) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .id(item.id)
                    .transition(.opacity.animation(.smooth(duration: 0.15)))
            }
            .contentShape(Rectangle())
            .onTapGesture { clipboard.copy(item) }
            .help(tr("點一下複製", "Click to copy"))
            footer
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.1 : 0.07))
        )
        .overlay {
            if isCopied {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black.opacity(0.65))
                    .overlay {
                        Label(tr("已複製", "Copied"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: isCopied)
        .onHover { isHovering = $0 }
        .contextMenu { ClipboardItemMenu(item: item, clipboard: clipboard) }
        // 卡片和按鈕列不跟著滾輪的彈簧動畫，換選取時原地更新
        .animation(nil, value: item.id)
    }

    @ViewBuilder
    private var content: some View {
        switch item.preview {
        case .text(let string):
            Text(String(string.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600)))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(4)
        case .link(let url):
            VStack(alignment: .leading, spacing: 4) {
                Label(url.host ?? url.absoluteString, systemImage: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                Text(url.absoluteString)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
        case .image(let image):
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text("\(Int(image.size.width)) × \(Int(image.size.height))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
            }
        case .files(let urls):
            HStack(spacing: 10) {
                HStack(spacing: -14) {
                    ForEach(urls.prefix(3), id: \.self) { url in
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path).bitmapCopy(pointSize: 64) ?? NSImage())
                            .resizable()
                            .frame(width: 40, height: 40)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(urls[0].lastPathComponent)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(urls.count > 1 ? tr("還有 \(urls.count - 1) 個項目", "\(urls.count - 1) more") : urls[0].deletingLastPathComponent().path)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if let bundleID = item.sourceBundleIdentifier, let icon = clipboard.appIcons[bundleID] {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13, height: 13)
            }
            Text([item.sourceApp ?? item.kindTitle, Self.relative(item.date)].joined(separator: " · "))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            Spacer(minLength: 6)
            RoundIconButton(
                symbol: item.isPinned ? "pin.slash" : "pin",
                label: item.isPinned ? tr("取消釘選", "Unpin") : tr("釘選（不會被自動刪掉）", "Pin (Never Removed Automatically)")
            ) {
                withAnimation(.smooth(duration: 0.2)) { clipboard.togglePin(item) }
            }
            .help(item.isPinned ? tr("取消釘選", "Unpin") : tr("釘選：排在最上面，不會被自動刪掉", "Pin: keep it at the top and never remove it automatically"))
            RoundIconButton(symbol: "trash", label: tr("從紀錄中移除", "Remove from History")) {
                withAnimation(.smooth(duration: 0.2)) { clipboard.remove(item) }
            }
            PillButton(title: tr("拷貝", "Copy"), isSelected: true, compact: true) { clipboard.copy(item) }
        }
        .frame(height: 22)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        formatter.locale = AppLanguage.current.locale
        return formatter
    }()

    /// 只在打開時算一次（不用 Text(_:style: .relative)，那個每秒都會重畫）。
    private static func relative(_ date: Date) -> String {
        Date().timeIntervalSince(date) < 10 ? tr("剛剛", "Just now") : relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

/// 滾輪的列和預覽共用的右鍵選單。
private struct ClipboardItemMenu: View {
    let item: ClipboardModel.Item
    let clipboard: ClipboardModel

    var body: some View {
        Button(tr("拷貝", "Copy")) { clipboard.copy(item) }
        Button(item.isPinned ? tr("取消釘選", "Unpin") : tr("釘選", "Pin")) {
            withAnimation(.smooth(duration: 0.2)) { clipboard.togglePin(item) }
        }
        if case .files = item.preview {
            Button(tr("在 Finder 中顯示", "Show in Finder")) { clipboard.revealInFinder(item) }
        }
        if case .link(let url) = item.preview {
            Button(tr("在瀏覽器中打開", "Open in Browser")) { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button(tr("從紀錄中移除", "Remove from History")) {
            withAnimation(.smooth(duration: 0.2)) { clipboard.remove(item) }
        }
        Button(tr("清除紀錄（保留釘選）", "Clear History (Keep Pinned)")) {
            withAnimation(.smooth(duration: 0.2)) { clipboard.removeAll() }
        }
        .disabled(clipboard.pinnedCount == clipboard.items.count)
    }
}

extension ClipboardModel.Item {
    /// 滾輪上那一列的文字。
    var wheelTitle: String {
        switch preview {
        case .text(let string):
            string.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        case .link(let url):
            url.host ?? url.absoluteString
        case .image(let image):
            tr("圖片 \(Int(image.size.width))×\(Int(image.size.height))", "Image \(Int(image.size.width))×\(Int(image.size.height))")
        case .files(let urls):
            urls.count > 1
                ? tr("\(urls[0].lastPathComponent) 等 \(urls.count) 個", "\(urls[0].lastPathComponent) and \(urls.count - 1) more")
                : urls[0].lastPathComponent
        }
    }

    var kindTitle: String {
        switch preview {
        case .text: tr("文字", "Text")
        case .link: tr("連結", "Link")
        case .image: tr("圖片", "Image")
        case .files: tr("檔案", "Files")
        }
    }
}

private struct EmptyClipboardView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            Text(tr("複製的文字、連結、圖片和檔案會出現在這裡", "Text, links, images and files you copy appear here"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(tr("點一下就能再複製一次；紀錄在結束 App 或重新開機後還會在", "Click one to copy it again. History stays after quitting or restarting"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

