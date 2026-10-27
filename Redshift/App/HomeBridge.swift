import Foundation
import Network
import SwiftUI

/// Afterglow's ESP32 bridge puts devices in Apple Home. Redshift pairs with it on its own token and
/// sends the blaster's address and key plus the IR codes for the buttons you pick. The bridge fires
/// them itself after that, so Home works with this phone asleep or away.
struct HomeBridgeLink: Codable, Equatable {
    var host = ""
    var port = 8080
    var token = ""
    var lastSent: Date?

    var isSet: Bool { !host.isEmpty && !token.isEmpty }

    static var stored: HomeBridgeLink {
        get {
            guard let d = UserDefaults.standard.data(forKey: "homeBridge"),
                  let v = try? JSONDecoder().decode(HomeBridgeLink.self, from: d) else { return HomeBridgeLink() }
            return v
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "homeBridge") }
    }
}

enum HomeBridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

enum HomeBridgeAPI {
    static let app = "redshift"

    static func url(_ host: String, _ port: Int, _ path: String) -> URL? { URL(string: "http://\(host):\(port)\(path)") }

    static func info(host: String, port: Int) async throws -> [String: Any] {
        guard let u = url(host, port, "/api/info") else { throw HomeBridgeError.message("Bad address.") }
        var req = URLRequest(url: u)
        req.timeoutInterval = 4
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["app"] as? String == "afterglow-bridge" else { throw HomeBridgeError.message("That isn't an Afterglow bridge.") }
        return obj
    }

    static func claim(host: String, port: Int) async throws -> String {
        guard let u = url(host, port, "/api/dev/claim?app=\(app)") else { throw HomeBridgeError.message("Bad address.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        let (data, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 409 {
            throw HomeBridgeError.message("The bridge is already paired with Redshift on another install. In Afterglow › Settings › Apple Home bridge, tap Reset Redshift pairing, then pair here again.")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let t = obj["token"] as? String else {
            throw HomeBridgeError.message("The bridge didn't hand out a token. Update its firmware from Afterglow.")
        }
        return t
    }

    /// True when the bridge restarts to add the device to Home.
    static func send(_ body: [String: Any], _ link: HomeBridgeLink) async throws -> Bool {
        guard let u = url(link.host, link.port, "/api/dev/config?app=\(app)") else { throw HomeBridgeError.message("Bad address.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(link.token, forHTTPHeaderField: "X-Device-Token")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw HomeBridgeError.message("The bridge doesn't know this phone anymore. Forget it here and pair again.") }
        guard code == 200, let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HomeBridgeError.message("Bridge said: \(String(decoding: data, as: UTF8.self))")
        }
        return obj["restart"] as? Bool ?? false
    }
}

/// Finds bridges by Bonjour (_afterglow._tcp).
@MainActor
final class HomeBridgeFinder: ObservableObject {
    struct Found: Hashable { var name: String; var host: String; var port: Int }
    @Published var found: [Found] = []
    @Published var searching = false
    private var browser: NWBrowser?

    func start() {
        stop()
        searching = true
        found = []
        let b = NWBrowser(for: .bonjour(type: "_afterglow._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            for r in results {
                guard case .service(let name, _, _, _) = r.endpoint else { continue }
                Task { await self?.resolve(r.endpoint, name: name) }
            }
        }
        b.start(queue: .main)
        browser = b
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            searching = false
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        searching = false
    }

    private func resolve(_ endpoint: NWEndpoint, name: String) async {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let c = NWConnection(to: endpoint, using: params)
        let result: (String, Int)? = await withCheckedContinuation { cont in
            let once = OnceFlag()
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let h, let p)? = c.currentPath?.remoteEndpoint, once.fire() {
                        var host = "\(h)"
                        if let pct = host.firstIndex(of: "%") { host = String(host[..<pct]) }
                        cont.resume(returning: (host, Int(p.rawValue)))
                    } else if once.fire() { cont.resume(returning: nil) }
                    c.cancel()
                case .failed, .cancelled:
                    if once.fire() { cont.resume(returning: nil) }
                default: break
                }
            }
            c.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                if once.fire() { cont.resume(returning: nil); c.cancel() }
            }
        }
        guard let r = result, !found.contains(where: { $0.host == r.0 }) else { return }
        found.append(Found(name: name, host: r.0, port: r.1))
    }
}

// MARK: - What Redshift sends

/// Which remotes and buttons go to Apple Home. Remote id -> key ids. "power" becomes an on/off
/// switch; anything else becomes a one-tap button.
enum HomeSelection {
    static var stored: [String: [String]] {
        get {
            if let d = UserDefaults.standard.data(forKey: "homeSelection"),
               let v = try? JSONDecoder().decode([String: [String]].self, from: d) { return v }
            // First time: the heater's power, since the TV and sound bar have their own tiles.
            var out: [String: [String]] = [:]
            for r in Store.shared.remotes where r.kind == .heater && r.key("power")?.isReady == true {
                out[r.id.uuidString] = ["power"]
            }
            return out
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "homeSelection") }
    }
}

extension Store {
    func homeBridgeConfig(_ selection: [String: [String]]) -> (body: [String: Any]?, problem: String?) {
        guard let id = config.devId, let key = config.localKey, key.count == 16, let host = config.host, !host.isEmpty else {
            return (nil, "Set up the blaster first.")
        }
        func dps(_ code: String) -> [String: Any] { IRCommand.send(code, format).mapValues { $0.any } }
        var list: [[String: Any]] = []
        for r in remotes {
            guard let keys = selection[r.id.uuidString], !keys.isEmpty else { continue }
            var o: [String: Any] = ["id": r.id.uuidString, "name": r.name, "kind": r.kind.rawValue]
            if keys.contains("power"), let c = r.key("power")?.activeCode { o["power"] = dps(c) }
            o["buttons"] = keys.filter { $0 != "power" }.compactMap { k -> [String: Any]? in
                guard let key = r.key(k), let c = key.activeCode else { return nil }
                return ["name": "\(r.name) \(key.label)", "dps": dps(c)]
            }
            list.append(o)
        }
        if list.isEmpty { return (nil, "Pick at least one remote below.") }
        return (["blaster": ["id": id, "key": key, "ip": host, "ver": config.version ?? 3.3], "remotes": list], nil)
    }
}

// MARK: - Screen

struct HomeBridgeView: View {
    @EnvironmentObject var store: Store
    @StateObject private var finder = HomeBridgeFinder()
    @State private var link = HomeBridgeLink.stored
    @State private var selection = HomeSelection.stored
    @State private var status: String?
    @State private var busy = false
    @State private var manualHost = ""

    var body: some View {
        List {
            Section {
                Text("Afterglow's ESP32 bridge can put IR remotes in Apple Home. Power becomes an on/off switch; other buttons become one-tap buttons. IR can't report back, so the switch shows what was last sent, not what the device is really doing. The TV and sound bar already have proper tiles (Afterglow and Subwave), so leave those off unless you want extra buttons.")
                    .font(.footnote)
            }

            Section("In Apple Home") {
                ForEach(store.remotes) { r in
                    let rid = r.id.uuidString
                    DisclosureGroup {
                        ForEach(r.keys.filter(\.isReady)) { k in
                            Toggle(isOn: Binding(
                                get: { selection[rid]?.contains(k.id) == true },
                                set: { on in
                                    var keys = selection[rid] ?? []
                                    if on { if !keys.contains(k.id) && (k.id == "power" || keys.filter({ $0 != "power" }).count < 8) { keys.append(k.id) } }
                                    else { keys.removeAll { $0 == k.id } }
                                    selection[rid] = keys.isEmpty ? nil : keys
                                    HomeSelection.stored = selection
                                })) {
                                Text(k.id == "power" ? "Power (switch)" : k.label)
                            }
                        }
                        if r.keys.filter(\.isReady).isEmpty {
                            Text("No buttons learned on this remote yet.").font(.footnote).foregroundStyle(.secondary)
                        }
                    } label: {
                        HStack {
                            Image(systemName: r.kind.symbol).foregroundStyle(r.kind.accent)
                            Text(r.name)
                            Spacer()
                            let n = selection[rid]?.count ?? 0
                            Text(n == 0 ? "Off" : "\(n)").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if link.isSet {
                Section {
                    LabeledContent("Bridge", value: link.host)
                    if let d = link.lastSent { LabeledContent("Last sent", value: d.formatted(date: .abbreviated, time: .shortened)) }
                    Button { Task { await send() } } label: {
                        Label(busy ? "Sending…" : "Send to Apple Home", systemImage: "arrow.up.circle")
                    }
                    .disabled(busy)
                    Button("Forget this bridge", role: .destructive) {
                        link = HomeBridgeLink()
                        HomeBridgeLink.stored = link
                        finder.start()
                    }
                } footer: {
                    Text("Send again after changing what's picked or re-learning a button. Adding or removing remotes and buttons restarts the bridge (about 20 s) so Home sees them.")
                }
            } else {
                Section {
                    if finder.searching { HStack { ProgressView(); Text("Looking for the bridge…") } }
                    ForEach(finder.found, id: \.self) { f in
                        Button { Task { await pair(f.host, f.port) } } label: { LabeledContent(f.name, value: f.host) }
                    }
                    Button("Search again") { finder.start() }
                    HStack {
                        TextField("Or type its IP", text: $manualHost).keyboardType(.decimalPad)
                        Button("Pair") { Task { await pair(manualHost.trimmingCharacters(in: .whitespaces), 8080) } }
                            .disabled(manualHost.isEmpty)
                    }
                } header: {
                    Text("Pair")
                } footer: {
                    Text("No bridge yet? Set one up from Afterglow › Settings › Apple Home bridge.")
                }
            }
            if let status { Section { Text(status).font(.footnote) } }
        }
        .navigationTitle("Apple Home")
        .onAppear {
            link = HomeBridgeLink.stored
            if !link.isSet { finder.start() }
        }
        .onDisappear { finder.stop() }
    }

    private func pair(_ host: String, _ port: Int) async {
        guard !host.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await HomeBridgeAPI.info(host: host, port: port)
            let token = try await HomeBridgeAPI.claim(host: host, port: port)
            link = HomeBridgeLink(host: host, port: port, token: token)
            HomeBridgeLink.stored = link
            busy = false
            await send()
        } catch {
            status = "Couldn't pair: \(error.localizedDescription)"
        }
    }

    private func send() async {
        let built = store.homeBridgeConfig(selection)
        guard let body = built.body else { status = built.problem; return }
        busy = true
        defer { busy = false }
        do {
            let restart = try await HomeBridgeAPI.send(body, link)
            link.lastSent = .now
            HomeBridgeLink.stored = link
            status = restart ? "Sent. The bridge is restarting to add them to Apple Home (about 20 s). They show up under the bridge; no new pairing needed."
                             : "Sent. Apple Home is up to date."
        } catch {
            status = error.localizedDescription
        }
    }
}
