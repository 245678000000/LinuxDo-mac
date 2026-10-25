import Foundation

@main
struct CoreTests {
    static var failed = 0
    static func check(_ value: Bool, _ name: String) { if !value { failed += 1; print("FAIL", name) } }
    static func main() {
        check(AppConfig.isInternal(URL(string: "https://linux.do/t/1")), "linux.do")
        check(AppConfig.isInternal(URL(string: "https://cdn.linux.do/a")), "subdomain")
        check(!AppConfig.isInternal(URL(string: "https://evil-linux.do")), "suffix boundary")
        check(!AppConfig.isInternal(URL(string: "https://linux.do.evil")), "host boundary")
        check(!AppConfig.isInternal(URL(string: "javascript://linux.do")), "scheme")
        let search = AppConfig.searchURL("玻璃 & mac")
        check(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "玻璃 & mac", "search query")
        check(ProxyEndpoint.parse("socks5://127.0.0.1:7890") == ProxyEndpoint(host: "127.0.0.1", port: 7890, socks: true), "socks")
        check(ProxyEndpoint.parse("http://user:pw@127.0.0.1:7890") == nil, "proxy credentials")
        check(ProxyEndpoint.parse("http://127.0.0.1:70000") == nil, "proxy port")
        check(safeDownloadName("../../secret.txt") == "secret.txt", "download traversal")
        let dir = URL(fileURLWithPath: "/tmp/downloads")
        let first = uniqueDownloadURL(directory: dir, filename: "a.txt", exists: { _ in false })
        let second = uniqueDownloadURL(directory: dir, filename: "a.txt", reserved: [first], exists: { _ in false })
        check(second.lastPathComponent == "a (1).txt", "concurrent download names")
        check(PageTitle.parse("(12+) 最新") == PageTitle(text: "最新", badge: "12+"), "title badge")
        let suite = "LinuxDoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = ReadingStore(defaults: defaults)
        store.save(.init(url: "https://linux.do/t/1", x: 0, y: 900, postID: "4", offset: 20, updated: 1))
        store.save(.init(url: "https://example.com", x: 0, y: 1, postID: nil, offset: nil, updated: 2))
        store.save(.init(url: "https://linux.do/t/2", x: 0, y: .nan, postID: nil, offset: nil, updated: 3))
        check(ReadingStore(defaults: defaults).position(for: URL(string: "https://linux.do/t/1")!)?.postID == "4", "reading persistence")
        check(store.positions.count == 1, "reading validation")
        defaults.removePersistentDomain(forName: suite)
        print(failed == 0 ? "PASS core tests" : "FAILED \(failed)")
        exit(failed == 0 ? 0 : 1)
    }
}
