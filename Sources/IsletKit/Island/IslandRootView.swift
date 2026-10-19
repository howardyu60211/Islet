import SwiftUI

/// 面板的根視圖：島貼在面板頂端中央，其餘透明。
struct IslandRootView: View {
    let island: IslandViewModel

    var body: some View {
        IslandView(island: island)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
    }
}

/// 黑色的島本體：大小、圓角、內容都跟著 presentation 用彈簧動畫變化。
struct IslandView: View {
    let island: IslandViewModel

    var body: some View {
        let presentation = island.presentation
        let metrics = island.metrics
        let shape = NotchShape(topRadius: metrics.topRadius, bottomRadius: metrics.bottomRadius)

        ZStack(alignment: .top) {
            IslandContent(island: island, presentation: presentation)
                .padding(.horizontal, metrics.topRadius)
                .frame(width: metrics.frameSize.width, height: metrics.frameSize.height, alignment: .top)
                .id(presentation.contentKey)
                .transition(.islandContent)
        }
        .frame(width: metrics.frameSize.width, height: metrics.frameSize.height)
        .background(shape.fill(.black))
        .clipShape(shape)
        // 陰影放在裁切外面另一層，不跟著內容（音波）重繪。
        // 這層要一直存在、只改陰影強度：用 if 插入的話新 view 會直接以展開後的
        // 最終大小淡入，外框就會跟正在彈簧變形的本體分離，最後才「pop」對齊。
        .background {
            shape
                .fill(.black)
                .shadow(
                    color: .black.opacity(presentation.isExpanded ? 0.5 : 0),
                    radius: presentation.isExpanded ? 14 : 0,
                    y: presentation.isExpanded ? 6 : 0
                )
        }
        .contentShape(shape)
        // 展開後只讓裡面的按鈕接收點擊，收合時點島本身才有作用
        .gesture(
            TapGesture().onEnded { island.handleTap() },
            including: presentation.isExpanded ? .subviews : .all
        )
        // 檔案直接丟到島上（不在投放區上）也加入暫存架
        .fileDropDestination { urls in
            island.preferences.shelfEnabled && island.shelf.add(urls) > 0
        }
        .animation(presentation.isExpanded ? .islandOpen : .islandClose, value: presentation)
    }
}

private struct IslandContent: View {
    let island: IslandViewModel
    let presentation: IslandPresentation

    var body: some View {
        switch presentation {
        case .idle:
            Color.clear
        case .compact(let activity):
            CompactView(island: island, activity: activity)
        case .banner(let event):
            BannerView(island: island, event: event)
        case .expanded:
            ExpandedView(island: island)
        }
    }
}

extension Animation {
    static let islandOpen = Animation.spring(duration: 0.42, bounce: 0.28)
    static let islandClose = Animation.spring(duration: 0.36, bounce: 0.04)
}

private struct IslandContentTransition: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        // 不用 blur：就算半徑是 0 也會多一個離屏繪製，內容在動時很耗 CPU
        content
            .opacity(isActive ? 0 : 1)
            .scaleEffect(isActive ? 0.9 : 1, anchor: .top)
    }
}

extension AnyTransition {
    /// 內容出現時晚一點點、縮放淡入；消失時很快淡出，讓島的形狀先動。
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandContentTransition(isActive: true),
                identity: IslandContentTransition(isActive: false)
            )
            .animation(.smooth(duration: 0.3).delay(0.07)),
            removal: .modifier(
                active: IslandContentTransition(isActive: true),
                identity: IslandContentTransition(isActive: false)
            )
            .animation(.smooth(duration: 0.12))
        )
    }
}
