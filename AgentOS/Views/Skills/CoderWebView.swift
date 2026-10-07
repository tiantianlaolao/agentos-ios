import SwiftUI
import WebKit
import Photos

/// Native shell for the existing Chinese workbench. Every opening starts with a
/// fresh, nonpersistent cookie store and authenticates against this app's server.
struct CoderWorkstationView: View {
    let action: CoderAction
    @Environment(\.dismiss) private var dismiss
    @State private var model = CoderWebModel()
    @State private var store = CoderStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                CoderWebContainer(model: model)
                if model.loading { ProgressView("正在打开造物台…").padding(20).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 12)) }
                if let error = model.error {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark").font(.largeTitle)
                        Text(error).multilineTextAlignment(.center)
                        Button("重试") { Task { await model.open(action) } }.buttonStyle(.borderedProminent)
                    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(AppTheme.background)
                }
            }
            .navigationTitle("造物台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("返回艾嘿") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { model.showCredits = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                            Text(store.balance.map { String($0) } ?? "—").monospacedDigit()
                        }
                    }
                    .accessibilityLabel(store.balance.map { "\($0) 积分，充值与消耗明细" } ?? "积分余额加载中，充值与消耗明细")
                }
            }
        }
        .task { await model.open(action) }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            store.balance = nil
            while !Task.isCancelled {
                await store.refreshBalance()
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
        .sheet(item: $model.shareItem, onDismiss: { model.cleanExports() }) { item in CoderShareSheet(items: item.items) }
        .sheet(item: $model.browser) { item in
            NavigationStack {
                CoderBrowser(url: item.url, model: model)
                    .navigationTitle("浏览作品").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { model.browser = nil } } }
            }
        }
        .sheet(isPresented: $model.showCredits, onDismiss: {
            let resume = store.shouldResumeCreation
            store.shouldResumeCreation = false
            model.refreshBalance(resumePending: resume)
        }) {
            CoderCreditsView(loadLedger: { try await model.loadLedger() })
        }
        .alert("造物台", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("知道了") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
        .onDisappear { model.webView?.stopLoading() }
    }
}

struct CoderShareItem: Identifiable { let id = UUID(); let items: [Any] }
struct CoderBrowserItem: Identifiable { let id = UUID(); let url: URL }

@Observable @MainActor
final class CoderWebModel: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var loading = true
    var error: String?
    var notice: String?
    var shareItem: CoderShareItem?
    var browser: CoderBrowserItem?
    var showCredits = false
    var webView: WKWebView?
    private(set) var baseURL: URL?
    private(set) var dataStore = WKWebsiteDataStore.nonPersistent()
    private var temporaryFiles: [URL] = []
    private var opening = false

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(CoderMessageProxy(self), name: "aiheyCoder")
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self; view.uiDelegate = self
        view.isOpaque = false; view.backgroundColor = .clear
        view.scrollView.contentInsetAdjustmentBehavior = .never
        webView = view
        return view
    }

    func open(_ action: CoderAction) async {
        guard !opening else { return }
        opening = true
        defer { opening = false }
        loading = true; error = nil
        do {
            guard let token = try await DatabaseService.shared.getSetting(key: "auth_token"), !token.isEmpty else { throw CoderError.message("请先登录 AIHEY，再打开造物台") }
            let configURL = URL(string: ServerConfig.shared.httpBaseURL + "/api/coder-app/config")!
            var configRequest = URLRequest(url: configURL)
            configRequest.timeoutInterval = 20
            configRequest.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: configRequest)
            guard let config = try? JSONDecoder().decode(CoderConfiguration.self, from: data) else {
                throw CoderError.message("当前服务尚未准备好造物台，请稍后再试")
            }
            guard (response as? HTTPURLResponse)?.statusCode == 200, config.ok,
                  let raw = config.baseUrl, let url = URL(string: raw),
                  url.scheme == "https", url.user == nil, url.password == nil,
                  let host = url.host, host.hasSuffix(".tybbtech.com"), config.bridgeVersion == 1 else {
                throw CoderError.message(config.error ?? "当前服务尚未准备好造物台，请稍后再试")
            }
            baseURL = url
            var request = URLRequest(url: url.appendingPathComponent("app-entry"))
            request.httpMethod = "POST"; request.timeoutInterval = 30
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["token": token, "platform": "ios", "prompt": action.prompt, "remix": action.remix ?? ""])
            makeWebView().load(request)
        } catch { self.error = error.localizedDescription; loading = false }
    }

    /// Reuse the authenticated workbench cookie and its existing grouped ledger.
    /// No second login, account token in JavaScript, or cross-environment fallback.
    func loadLedger() async throws -> [CoderLedgerGroup] {
        guard !loading, error == nil, let webView, isWorkbench(webView.url) else {
            throw CoderError.message("暂时无法读取消耗明细，请先打开造物台后重试。")
        }
        let script = """
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 15000);
        try {
            const response = await fetch('/api/credits-ledger', {
                method: 'POST', headers: {'Content-Type': 'application/json'},
                body: '{}', signal: controller.signal
            });
            if (!response.ok) throw new Error('ledger unavailable');
            return JSON.stringify(await response.json());
        } finally { clearTimeout(timer); }
        """
        do {
            let text: String = try await withCheckedThrowingContinuation { continuation in
                webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                    switch result {
                    case .success(let value):
                        guard let text = value as? String else {
                            continuation.resume(throwing: CoderError.message("消耗明细暂时无法加载，请重试。"))
                            return
                        }
                        continuation.resume(returning: text)
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
            }
            guard let data = text.data(using: .utf8) else {
                throw CoderError.message("消耗明细暂时无法加载，请重试。")
            }
            let response = try JSONDecoder().decode(CoderLedgerResponse.self, from: data)
            guard response.ok else {
                throw CoderError.message(response.need == "login" ? "登录已失效，请返回艾嘿重新登录。" : "消耗明细暂时无法加载，请重试。")
            }
            return response.groups ?? []
        } catch let error as CoderError { throw error }
        catch { throw CoderError.message("消耗明细加载失败，请检查网络后重试。") }
    }

    func refreshBalance(resumePending: Bool = false) {
        let resume = resumePending ? "true" : "false"
        webView?.evaluateJavaScript("(async()=>{if(typeof refreshBalance==='function')await refreshBalance();if(\(resume)&&typeof resumeAfterPay==='function')resumeAfterPay();})()", completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { error = "页面已暂停，请点重试重新打开"; loading = false }
    private func failed(_ error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { self.error = "连接中断，请检查网络后重试"; loading = false }
    }

    func isWorkbench(_ url: URL?) -> Bool {
        guard let url, let baseURL else { return false }
        return url.scheme == baseURL.scheme && url.host == baseURL.host && url.port == baseURL.port
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if isWorkbench(url) && ["/", "/index.html", "/app-entry"].contains(url.path) {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        if url.scheme == "https" { browser = CoderBrowserItem(url: url) }
    }


    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        CoderDialogs.present(webView, message: message, kind: 0, value: nil) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        CoderDialogs.present(webView, message: message, kind: 1, value: nil) { completionHandler($0 != nil) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        CoderDialogs.present(webView, message: prompt, kind: 2, value: defaultText, completion: completionHandler)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.scheme == "https" { browser = CoderBrowserItem(url: url) }
        return nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, isWorkbench(message.frameInfo.request.url),
              ["/", "/index.html"].contains(message.frameInfo.request.url?.path ?? ""),
              let body = message.body as? [String: Any], body["version"] as? Int == 1,
              let id = body["id"] as? String, id.count < 40, let method = body["method"] as? String else { return }
        let args = body["args"] as? [String: Any] ?? [:]
        Task { @MainActor in
            do {
                switch method {
                case "copy":
                    guard let text = args["text"] as? String, text.count <= 2 * 1024 * 1024 else { throw CoderError.message("内容过长") }
                    UIPasteboard.general.string = text
                case "open":
                    browser = CoderBrowserItem(url: try httpsURL(args["url"]))
                case "share":
                    let url = try httpsURL(args["url"])
                    shareItem = CoderShareItem(items: [String((args["text"] as? String ?? "我的作品").prefix(500)), url])
                case "saveImage": try await saveImage(args["dataUrl"])
                case "export": try await exportProject(args["projectId"])
                case "credits": showCredits = true
                case "authExpired": error = "登录已失效，请返回艾嘿重新登录后再打开造物台"
                default: throw CoderError.message("当前版本不支持这项操作")
                }
                reply(id, error: nil)
            } catch { reply(id, error: error.localizedDescription) }
        }
    }

    private func httpsURL(_ raw: Any?) throws -> URL {
        guard let raw = raw as? String, raw.count <= 8192, let url = URL(string: raw), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else { throw CoderError.message("无法打开这个链接") }
        return url
    }

    private func saveImage(_ value: Any?) async throws {
        guard let text = value as? String, text.count <= 16 * 1024 * 1024,
              text.hasPrefix("data:image/png;base64,") || text.hasPrefix("data:image/jpeg;base64,"),
              let comma = text.firstIndex(of: ","), let bytes = Data(base64Encoded: String(text[text.index(after: comma)...])),
              let image = UIImage(data: bytes) else { throw CoderError.message("海报图片无效或过大") }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw CoderError.message("请在系统设置中允许 AIHEY 保存图片") }
        try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from: image) }
    }

    private func exportProject(_ value: Any?) async throws {
        guard let id = value as? String, id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil,
              let baseURL else { throw CoderError.message("作品不存在") }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/export"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 60
        let cookies = await dataStore.httpCookieStore.allCookies().filter {
            $0.name == "lc_token" && $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == baseURL.host
        }
        for (key, val) in HTTPCookie.requestHeaderFields(with: cookies) { request.setValue(val, forHTTPHeaderField: key) }
        let session = URLSession(configuration: .ephemeral, delegate: CoderNoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 50 * 1024 * 1024,
              data.starts(with: [0x50, 0x4b]) else { throw CoderError.message("导出失败，请重试") }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("AIHEY-\(id)-\(UUID().uuidString).zip")
        try data.write(to: file, options: .atomic)
        temporaryFiles.append(file)
        shareItem = CoderShareItem(items: [file])
    }

    func cleanExports() {
        for file in temporaryFiles { try? FileManager.default.removeItem(at: file) }
        temporaryFiles.removeAll()
    }

    private func reply(_ id: String, error: String?) {
        var value: [String: Any] = ["id": id, "ok": error == nil]
        if let error { value["error"] = error }
        guard let data = try? JSONSerialization.data(withJSONObject: value), let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.AIHEYCoderReply && window.AIHEYCoderReply(\(json));", completionHandler: nil)
    }

    func remix(_ id: String) {
        guard let baseURL, id.range(of: "^[A-Za-z0-9_-]{1,80}$", options: .regularExpression) != nil else { return }
        browser = nil
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "embedded", value: "true"), URLQueryItem(name: "native", value: "ios"), URLQueryItem(name: "remix", value: id)]
        if let url = components.url { loading = true; webView?.load(URLRequest(url: url)) }
    }
}

private struct CoderConfiguration: Decodable { let ok: Bool; var baseUrl: String?; var bridgeVersion: Int?; var error: String? }
private final class CoderNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
enum CoderError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let value) = self { return value }; return nil } }

/// WKUserContentController owns its handlers; use a weak proxy to avoid a cycle.
@MainActor private final class CoderMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: CoderWebModel?
    init(_ target: CoderWebModel) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { target?.userContentController(controller, didReceive: message) }
}
private struct CoderWebContainer: UIViewRepresentable {
    let model: CoderWebModel
    func makeUIView(context: Context) -> WKWebView { model.makeWebView() }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
private struct CoderShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ view: UIActivityViewController, context: Context) {}
}
private struct CoderBrowser: UIViewRepresentable {
    let url: URL
    let model: CoderWebModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = model.dataStore
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator; view.uiDelegate = context.coordinator
        view.load(URLRequest(url: url)); return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: CoderWebModel
        init(_ model: CoderWebModel) { self.model = model }
        func webView(_ view: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if [model.baseURL?.host, "agentos.tybbtech.com"].contains(url.host),
               let remix = q.first(where: { $0.name == "remix" })?.value {
                decisionHandler(.cancel); model.remix(remix); return
            }
            decisionHandler(url.scheme == "https" ? .allow : .cancel)
        }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        CoderDialogs.present(webView, message: message, kind: 0, value: nil) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        CoderDialogs.present(webView, message: message, kind: 1, value: nil) { completionHandler($0 != nil) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        CoderDialogs.present(webView, message: prompt, kind: 2, value: defaultText, completion: completionHandler)
    }

        func webView(_ view: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, url.scheme == "https" { view.load(action.request) }; return nil
        }
    }
}


@MainActor private enum CoderDialogs {
    static func present(_ view: WKWebView, message: String, kind: Int, value: String?, completion: @escaping (String?) -> Void) {
        guard var presenter = view.window?.rootViewController else { completion(nil); return }
        while let next = presenter.presentedViewController { presenter = next }
        guard !(presenter is UIAlertController) else { completion(nil); return }
        let alert = UIAlertController(title: "造物台", message: String(message.prefix(2000)), preferredStyle: .alert)
        if kind == 2 { alert.addTextField { $0.text = value } }
        if kind != 0 { alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(nil) }) }
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completion(kind == 2 ? alert.textFields?.first?.text ?? "" : "ok") })
        presenter.present(alert, animated: true)
    }
}
