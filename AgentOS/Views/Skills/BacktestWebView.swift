import SwiftUI
import WebKit

/// Full-screen WKWebView for the Backtest Assistant workstation.
/// Loads quant.tybbtech.com in embedded mode with the user's auth token.
struct BacktestWorkstationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()

                BacktestWebViewRepresentable(isLoading: $isLoading)
                    .ignoresSafeArea(edges: .bottom)

                if isLoading {
                    ProgressView()
                        .tint(AppTheme.primary)
                        .scaleEffect(1.2)
                }
            }
            .navigationTitle("回测助手")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
    }
}

/// UIViewRepresentable wrapper for WKWebView
struct BacktestWebViewRepresentable: UIViewRepresentable {
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.bounces = true
        webView.allowsBackForwardNavigationGestures = true

        // Build embedded URL with auth token and WS URL
        Task {
            let token = (try? await DatabaseService.shared.getSetting(key: "auth_token")) ?? ""
            let wsUrl = ServerConfig.shared.wsURL
            let urlString = "https://quant.tybbtech.com/?embedded=true&token=\(token)&wsUrl=\(wsUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? wsUrl)"

            if let url = URL(string: urlString) {
                await MainActor.run {
                    webView.load(URLRequest(url: url))
                }
            }
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: BacktestWebViewRepresentable

        init(parent: BacktestWebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                parent.isLoading = false
            }
        }
    }
}
