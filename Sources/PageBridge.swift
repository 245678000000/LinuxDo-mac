import Cocoa
import WebKit

/// Isolated script world. No cookies, account data, post bodies or draft text cross the bridge.
enum PageBridge {
    static var source: String {
        let preview = AppConfig.preview ? "true" : "false"
        return #"""
        (() => {
          const allowed = /(^|\.)linux\.do$/i.test(location.hostname) || (PREVIEW && location.protocol === 'file:');
          if (!allowed || window.__linuxDoNative) return;
          let timer, restoring = false, cancelled = false, lastDraft = false;
          const send = (type, data = {}) => window.webkit.messageHandlers.nativeState.postMessage({type, ...data});
          const style = document.createElement('style');
          style.id = 'linuxdo-native-reading';
          style.textContent = `
            html[data-linuxdo-reading="true"] .cooked {
              font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
              font-size: var(--linuxdo-font, 16px); line-height: var(--linuxdo-line, 1.75);
              overflow-wrap: break-word;
            }
            html[data-linuxdo-reading="true"] .cooked p { line-height: inherit; }
            html[data-linuxdo-reading="true"] .cooked pre, html[data-linuxdo-reading="true"] .cooked code {
              font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            }
            html[data-linuxdo-sidebar="true"] .sidebar-wrapper { display: none !important; }
            html[data-linuxdo-sidebar="true"] body.has-sidebar-page #main-outlet-wrapper { grid-template-columns: minmax(0, 1fr) !important; }
            html[data-linuxdo-sidebar="true"] .header-sidebar-toggle { display: none !important; }
          `;
          document.head.appendChild(style);
          function hasDraft() {
            return Array.from(document.querySelectorAll('.d-editor-input, #reply-control textarea, textarea[data-linuxdo-draft]'))
              .some(el => el.value.trim().length > 0 && el.getClientRects().length > 0);
          }
          function reportDraft() {
            const value = hasDraft();
            if (lastDraft !== value) { lastDraft = value; send('draft', {value}); }
          }
          function capture() {
            if (restoring) return;
            const posts = document.querySelectorAll('[data-post-id]');
            let anchor = null;
            for (const el of posts) { const r = el.getBoundingClientRect(); if (r.bottom > 0) { anchor = el; break; } }
            send('position', {url: location.href, x: Math.max(0, scrollX), y: Math.max(0, scrollY),
              postID: anchor ? anchor.getAttribute('data-post-id') : null,
              offset: anchor ? anchor.getBoundingClientRect().top : null});
          }
          function stopRestoring() { cancelled = true; restoring = false; }
          addEventListener('wheel', stopRestoring, {passive:true});
          addEventListener('pointerdown', stopRestoring, {passive:true});
          addEventListener('keydown', stopRestoring, {passive:true});
          addEventListener('scroll', () => { clearTimeout(timer); timer = setTimeout(capture, 650); }, {passive:true});
          addEventListener('input', reportDraft, {passive:true, capture:true});
          addEventListener('change', reportDraft, {passive:true, capture:true});
          addEventListener('pagehide', capture);
          document.addEventListener('visibilitychange', () => { if (document.hidden) capture(); });
          window.__linuxDoNative = {
            capture, hasDraft,
            configure(options) {
              document.documentElement.dataset.linuxdoReading = String(options.reading);
              document.documentElement.dataset.linuxdoSidebar = String(options.sidebar);
              document.documentElement.style.setProperty('--linuxdo-font', options.font + 'px');
              document.documentElement.style.setProperty('--linuxdo-line', String(options.line));
            },
            restore(position) {
              if (cancelled || location.href !== position.url) return;
              restoring = true;
              let attempt = 0;
              function apply() {
                if (cancelled || location.href !== position.url) { restoring = false; return; }
                let target = position.y;
                if (position.postID) {
                  const anchor = Array.from(document.querySelectorAll('[data-post-id]')).find(el => el.getAttribute('data-post-id') === position.postID);
                  if (anchor) target = scrollY + anchor.getBoundingClientRect().top - (position.offset || 0);
                }
                scrollTo(position.x || 0, Math.max(0, target));
                if (++attempt < 4 && Math.abs(scrollY - target) > 20) setTimeout(apply, 350);
                else restoring = false;
              }
              apply();
            }
          };
          send('ready');
        })();
        """#.replacingOccurrences(of: "PREVIEW", with: preview)
    }
    static func configureScript(sidebarVisible: Bool) -> String {
        let options: [String: Any] = ["reading": Prefs.defaults.bool(forKey: Prefs.reading),
            "sidebar": sidebarVisible && Prefs.defaults.bool(forKey: Prefs.hideWebSidebar),
            "font": Prefs.boundedFont(Prefs.defaults.double(forKey: Prefs.fontSize)),
            "line": Prefs.boundedLineHeight(Prefs.defaults.double(forKey: Prefs.lineHeight))]
        return "window.__linuxDoNative?.configure(\(jsonString(options)));"
    }
}

final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
