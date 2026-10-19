import SwiftUI

enum RenderingContext {
    /// Debug 快照模式。ImageRenderer 畫不出背後是 AppKit view 的東西（拖放目標、捲動區），
    /// 快照時就換成畫得出來的版本。
    static var isSnapshot = false
}

extension View {
    /// 接受從 Finder 拖進來的檔案。
    @ViewBuilder
    func fileDropDestination(
        perform action: @escaping ([URL]) -> Bool,
        isTargeted: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        if RenderingContext.isSnapshot {
            self
        } else {
            dropDestination(for: URL.self) { urls, _ in
                action(urls)
            } isTargeted: { targeted in
                isTargeted(targeted)
            }
        }
    }
}

/// 橫向捲動區（快照模式下改成一般的 HStack）。
struct HorizontalScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if RenderingContext.isSnapshot {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                content()
            }
        }
    }
}
