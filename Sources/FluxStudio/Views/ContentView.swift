import SwiftUI

public enum NavigationTab: String, CaseIterable, Identifiable {
    case textToImage = "文字生成"
    case inpaint = "影像重繪 (Inpaint)"
    case modelHub = "模型倉庫"

    public var id: String { self.rawValue }

    public var icon: String {
        switch self {
        case .textToImage: return "text.badge.sparkles"
        case .inpaint: return "paintbrush.pointed"
        case .modelHub: return "shippingbox"
        }
    }
}

public struct ContentView: View {
    @State private var selectedTab: NavigationTab = .textToImage
    @StateObject private var canvasState = CanvasState()
    @ObservedObject private var modelManager = ModelManager.shared

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(NavigationTab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    HStack {
                        Label(tab.rawValue, systemImage: tab.icon)
                        Spacer()
                        if tab == .modelHub && modelManager.isDownloading {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 270)
            .navigationTitle("FluxStudio")
        } detail: {
            switch selectedTab {
            case .textToImage:
                TextToImageView()
            case .inpaint:
                InpaintCanvasView(state: canvasState)
            case .modelHub:
                ModelHubView()
            }
        }
        .onAppear {
            modelManager.refresh()
        }
    }
}
