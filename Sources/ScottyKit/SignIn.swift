import AppKit
import WebKit

@MainActor
final class SignIn: NSObject, NSWindowDelegate, WKNavigationDelegate {
  private static let profile = UUID(uuidString: "5C07C3E2-0D6B-4C1A-9C2E-7A1E5C4D2B10")!
  private static let autofill = """
    const form = document.getElementById('login');
    const user = document.getElementById('username');
    const pass = document.getElementById('passwordinput');
    const proceed = form?.querySelector('[name="_eventId_proceed"]');
    if (!user || !pass || !proceed || new URL(form.action, location.href).origin !== origin) return false;
    user.value = account;
    pass.value = password;
    form.requestSubmit(proceed);
    return true;
    """

  private let challenge: Challenge
  private let window: NSWindow
  private let web: WKWebView
  private var continuation: CheckedContinuation<String, any Error>?
  private var credentials: Credentials?
  private var deadline: Task<Void, Never>?

  private init(_ challenge: Challenge) {
    self.challenge = challenge
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.profile)
    web = WKWebView(frame: .zero, configuration: configuration)
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    super.init()
    window.title = "Sign in to Carnegie Mellon"
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.contentView = web
    window.delegate = self
    web.navigationDelegate = self
  }

  static func token(for challenge: Challenge, patience: Duration?) async throws -> String {
    let flow = SignIn(challenge)
    flow.web.configuration.userContentController.add(try await Trust.blocker())
    flow.credentials = try? await Credentials.load()
    let cookies = flow.web.configuration.websiteDataStore.httpCookieStore
    for stale in await cookies.allCookies() where stale.name == challenge.cookie {
      await cookies.deleteCookie(stale)
    }
    return try await withCheckedThrowingContinuation { continuation in
      flow.continuation = continuation
      flow.window.center()
      flow.web.load(URLRequest(url: challenge.login))
      guard let patience else {
        NSApp.activate(ignoringOtherApps: true)
        flow.window.makeKeyAndOrderFront(nil)
        flow.window.makeFirstResponder(flow.web)
        return
      }
      flow.window.orderFrontRegardless()
      flow.deadline = Task { [weak flow] in
        guard (try? await Task.sleep(for: patience)) != nil else { return }
        flow?.finish(.failure(ScottyError.needsAttention))
      }
    }
  }

  private func finish(_ result: Result<String, any Error>) {
    guard let continuation else { return }
    self.continuation = nil
    deadline?.cancel()
    window.delegate = nil
    window.close()
    continuation.resume(with: result)
  }

  func windowWillClose(_: Notification) { finish(.failure(CancellationError())) }

  func webView(_: WKWebView, decidePolicyFor action: WKNavigationAction) async
    -> WKNavigationActionPolicy
  {
    guard let url = action.request.url else { return .cancel }
    if url.scheme == "about" || Trust.allows(url, within: Trust.signIn) { return .allow }
    if action.targetFrame?.isMainFrame != false {
      let host = url.host() ?? url.absoluteString
      finish(.failure(ScottyError.failed("Sign-in tried to open \(host), outside CMU and Duo.")))
    }
    return .cancel
  }

  func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
    guard webView.url?.absoluteString.hasPrefix(challenge.final) == true else {
      return fill(webView)
    }
    Task {
      let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
      guard let token = cookies.first(where: { $0.name == challenge.cookie })?.value else { return }
      finish(.success(token))
    }
  }

  private func fill(_ webView: WKWebView) {
    guard let credentials, let url = webView.url, Trust.allows(url, within: Trust.campus),
      url.host() == Configuration.identityProvider, webView.hasOnlySecureContent
    else { return }
    Task {
      let arguments = [
        "account": credentials.account, "password": credentials.password,
        "origin": "https://\(Configuration.identityProvider)",
      ]
      let submitted = try? await webView.callAsyncJavaScript(
        Self.autofill, arguments: arguments, contentWorld: .defaultClient)
      if submitted as? Bool == true { self.credentials = nil }
    }
  }
}
