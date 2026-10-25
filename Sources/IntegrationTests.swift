#if DEBUG
import Cocoa
import WebKit

/// Opt-in offline GUI smoke test: LinuxDo --preview --self-test
final class IntegrationTests {
    private weak var app: AppDelegate?
    private var step = 0
    private var failures: [String] = []
    private let output = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("LinuxDoSelfTest.txt")
    init(app: AppDelegate) { self.app = app }
    func start() { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.next() } }
    private var controller: MainWindowController? { app?.windows.first }
    private func js(_ source: String, _ done: @escaping (Any?) -> Void) {
        controller?.webView.evaluateJavaScript(source) { value, _ in done(value) }
    }
    private func expect(_ ok: Bool, _ message: String) { if !ok { failures.append(message) } }
    private func later(_ seconds: Double = 0.8) { DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { self.next() } }
    private func next() {
        guard let c = controller else { finish("missing window"); return }
        step += 1
        switch step {
        case 1:
            if c.webView.isLoading || c.webView.url == nil { step = 0; later(0.5); return }
            expect(c.window?.toolbarStyle == .unified, "toolbar is unified")
            expect(c.window?.styleMask.contains(.fullSizeContentView) == true, "full size content")
            js("[getComputedStyle(document.querySelector('.cooked')).fontSize, getComputedStyle(document.querySelector('.sidebar-wrapper')).display].join('|')") { value in
                self.expect((value as? String) == "16px|none", "reading CSS and web sidebar integration: \(String(describing: value))"); self.later()
            }
        case 2:
            c.navigate(AppConfig.route("/top")); later(1.2)
        case 3:
            expect(c.webView.url?.query?.contains("route=/top") == true || c.webView.url?.query?.contains("route=%2Ftop") == true, "route navigation")
            expect(c.sidebar.table.selectedRow == 2, "sidebar selection follows route")
            c.navBack(nil); later(1.2)
        case 4:
            expect(c.webView.url?.query?.contains("top") != true, "back navigation")
            c.findBar.field.stringValue = "玻璃阅读样例"; c.findNext(nil); later()
        case 5:
            expect(c.findBar.status.stringValue == "找到匹配", "native find")
            c.hideFind(nil)
            js("scrollTo(0, 2200); window.__linuxDoNative.capture(); scrollY") { _ in self.later(1) }
        case 6:
            let pos = c.webView.url.flatMap { ReadingStore.shared.position(for: $0) }
            expect((pos?.y ?? 0) > 1500, "reading position captured")
            app?.makeWindow(url: c.webView.url); later(2)
        case 7:
            js("scrollY") { _ in }
            app?.windows.last?.webView.evaluateJavaScript("scrollY") { value, _ in
                self.expect(((value as? Double) ?? 0) > 1500, "reading position restored: \(String(describing: value))")
                self.app?.windows.last?.window?.performClose(nil); self.later()
            }
        case 8:
            js("document.querySelector('#draft').value='草稿'; document.querySelector('#draft').dispatchEvent(new Event('input', {bubbles:true})); true") { _ in self.later(0.5) }
        case 9:
            let eventSignal = c.hasUnsavedDraft
            c.refreshDraftState { live in
                self.expect(live, "live draft detection")
                if !eventSignal { self.failures.append("input event draft signal (live=\(live))") }
                self.js("document.querySelector('#draft').value=''; true") { _ in
                    c.refreshDraftState { value in self.expect(!value, "stale draft cleared"); self.later(0.3) }
                }
            }
        case 10:
            c.focusSearch(nil); c.searchItem?.searchField.stringValue = "SwiftUI & 玻璃"
            if let field = c.searchItem?.searchField { c.submitSearch(field) }; later(1.2)
        case 11:
            expect(c.webView.url?.absoluteString.contains("SwiftUI") == true, "toolbar search")
            finish(nil)
        default: finish(nil)
        }
    }
    private func finish(_ fatal: String?) {
        if let fatal { failures.append(fatal) }
        let text = failures.isEmpty ? "PASS 11 integration steps\n" : "FAIL\n" + failures.joined(separator: "\n") + "\n"
        try? text.write(to: output, atomically: true, encoding: .utf8)
        print(text)
        exit(failures.isEmpty ? 0 : 1)
    }
}
#endif
