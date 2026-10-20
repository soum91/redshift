import SwiftUI
import UIKit

enum LinkState: Equatable {
    case off, searching(String), connecting, connected(Double), failed(String)

    var text: String {
        switch self {
        case .off: return "Not connected"
        case .searching(let s): return s
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .failed(let e): return e
        }
    }

    var isConnected: Bool { if case .connected = self { return true } else { return false } }
    var isBusy: Bool {
        switch self {
        case .searching, .connecting: return true
        default: return false
        }
    }
}

struct LearnSession: Identifiable, Equatable {
    enum Phase: Equatable { case starting, waiting, captured(Int), failed(String) }
    let id = UUID()
    var remoteID: UUID
    var keyID: String
    var label: String
    var remoteName: String
    var phase: Phase = .starting
}

struct LogLine: Identifiable {
    let id = UUID()
    let time = Date()
    let text: String
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var config = BlasterConfig.stored { didSet { if config != oldValue { BlasterConfig.stored = config } } }
    @Published var remotes: [Remote] = RemoteStore.load() { didSet { RemoteStore.save(remotes) } }
    @Published var selected: UUID? {
        didSet { UserDefaults.standard.set(selected?.uuidString, forKey: "selectedRemote") }
    }
    @Published var state: LinkState = .off
    @Published var learnMode = false
    @Published var learning: LearnSession?
    @Published var log: [LogLine] = []
    @Published var toast: String?

    // One-time Smart Life sign-in, only to get the blaster's local key.
    @Published var token: TuyaToken? = TokenStore.load()
    @Published var devices: [DeviceInfo] = []
    @Published var loadingDevices = false
    @Published var setupError: String?

    private var link: LocalLink?
    private var connecting: Task<LocalLink, Error>?
    private var learnTimeout: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var seenDPs: Set<String> = []
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    init() {
        if let s = UserDefaults.standard.string(forKey: "selectedRemote"), let id = UUID(uuidString: s),
           remotes.contains(where: { $0.id == id }) {
            selected = id
        } else {
            selected = remotes.first?.id
        }
    }

    var current: Remote? { remotes.first { $0.id == selected } ?? remotes.first }
    var format: IRFormat { config.format }

    // MARK: - Smart Life (once)

    func signedIn(_ t: TuyaToken) {
        TokenStore.save(t)
        token = t
        Task { await loadDevices() }
    }

    func signOutCloud() {
        TokenStore.clear()
        token = nil
        devices = []
    }

    func loadDevices() async {
        guard let token else { return }
        loadingDevices = true
        setupError = nil
        defer { loadingDevices = false }
        do {
            let list = try await TuyaClient(token: token).allDevices()
            devices = list.sorted { a, b in
                if a.isBlaster != b.isBlaster { return a.isBlaster }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            if devices.isEmpty { setupError = "No devices came back from Smart Life." }
        } catch {
            if let te = error as? TuyaError, te.isAuth { signOutCloud() }
            setupError = error.localizedDescription
        }
    }

    func choose(_ d: DeviceInfo) {
        guard let key = d.localKey, !key.isEmpty else {
            setupError = "Smart Life didn't hand over a local key for \(d.name)."
            return
        }
        setBlaster(devId: d.id, key: key, name: d.name)
    }

    func setBlaster(devId: String, key: String, name: String?) {
        let sameDevice = config.devId == devId
        disconnect()
        config.devId = devId
        config.localKey = key
        config.name = name ?? config.name ?? "IR blaster"
        if !sameDevice {
            config.host = nil
            config.version = nil
            config.detected = nil
        }
        if config.host == nil { findOnWiFi() } else { connect() }
    }

    /// Pulls a fresh local key after the blaster was re-paired.
    func refreshKey() async {
        guard let devId = config.devId else { return }
        await loadDevices()
        if let d = devices.first(where: { $0.id == devId }), let key = d.localKey, !key.isEmpty {
            if key != config.localKey {
                config.localKey = key
                reconnect()
                show("Got a new local key")
            } else {
                show("Key is already current")
            }
        }
    }

    func forgetBlaster() {
        disconnect()
        config = BlasterConfig()
        state = .off
    }

    // MARK: - Connection

    func connect() {
        guard config.isReady, link == nil, connecting == nil else { return }
        Task { _ = try? await ensureLink() }
    }

    func disconnect() {
        connecting?.cancel()
        connecting = nil
        if let l = link { Task { await l.close() } }
        link = nil
        state = .off
    }

    func reconnect() {
        disconnect()
        connect()
    }

    func closed(_ why: String) {
        link = nil
        state = .failed(why)
    }

    @discardableResult
    func ensureLink() async throws -> LocalLink {
        if let l = link, await l.isOpen { return l }
        if let t = connecting { return try await t.value }
        let t = Task { try await self.openLink() }
        connecting = t
        do {
            let l = try await t.value
            connecting = nil
            return l
        } catch {
            connecting = nil
            throw error
        }
    }

    private func openLink() async throws -> LocalLink {
        guard let devId = config.devId, let key = config.localKey else { throw LocalError("Set up the blaster first.") }
        guard let host = config.host else { throw LocalError("The blaster's IP isn't known yet. Find it in Settings.") }
        state = .connecting
        let onDPS: @Sendable ([String: JSONValue]) -> Void = { dps in
            Task { @MainActor in Store.shared.receive(dps) }
        }
        let onClose: @Sendable (String) -> Void = { why in
            Task { @MainActor in Store.shared.closed(why) }
        }
        do {
            var result: (LocalLink, [String: JSONValue])?
            if let v = config.version {
                let l = LocalLink(devId: devId, host: host, localKey: key, version: v, onDPS: onDPS, onClose: onClose)
                do {
                    try await l.open()
                    result = (l, try await l.statusAfterOpen())
                } catch {
                    await l.close()
                }
            }
            let r: (LocalLink, [String: JSONValue])
            if let result {
                r = result
            } else {
                r = try await LocalLink.detect(devId: devId, host: host, localKey: key, knownDPs: [],
                                               onDPS: onDPS, onClose: onClose)
            }
            link = r.0
            config.version = r.0.version
            state = .connected(r.0.version)
            note("Connected to \(host), protocol \(String(format: "%.1f", r.0.version))")
            receive(r.1)
            if config.detected == nil {
                var f = IRCommand.hint(r.1)
                if f == nil { f = await probeFormat(r.0) }
                config.detected = f
                note("Command format: \(config.format.title)")
            }
            return r.0
        } catch {
            state = .failed("Couldn't reach the blaster: \(error.localizedDescription)")
            throw error
        }
    }

    /// Same trick as tinytuya: poke both formats with a harmless "exit learning" and see which data point answers.
    private func probeFormat(_ l: LocalLink) async -> IRFormat? {
        seenDPs = []
        try? await l.set(IRCommand.studyExit(.classic))
        try? await l.set(IRCommand.studyExit(.modern))
        try? await Task.sleep(nanoseconds: 600_000_000)
        if let dps = try? await l.query(), let h = IRCommand.hint(dps) { return h }
        if seenDPs.contains("201") || seenDPs.contains("202") { return .classic }
        if seenDPs.contains("1") || seenDPs.contains("2") { return .modern }
        return nil
    }

    /// Scans the Wi-Fi for anything on Tuya's port, then tries the blaster's key on all of them at once.
    func findOnWiFi() {
        guard let devId = config.devId, let key = config.localKey else { return }
        disconnect()
        state = .searching("Scanning your Wi-Fi…")
        Task {
            let hosts = await LocalScan.openHosts { n in
                Task { @MainActor in
                    if case .searching = Store.shared.state { Store.shared.state = .searching("Scanning your Wi-Fi… \(n)/254") }
                }
            }
            if hosts.isEmpty {
                state = .failed("Nothing on your Wi-Fi answered on Tuya's port. Allow Local Network for Redshift in iOS Settings, or type the blaster's IP.")
                return
            }
            state = .searching("Trying the key on \(hosts.count) Tuya device\(hosts.count == 1 ? "" : "s")…")
            let found: (String, Double)? = await withTaskGroup(of: (String, Double)?.self) { group in
                for host in hosts {
                    group.addTask {
                        guard let r = try? await LocalLink.detect(devId: devId, host: host, localKey: key, knownDPs: [],
                                                                  onDPS: { _ in }, onClose: { _ in }) else { return nil }
                        await r.0.close()
                        return (host, r.0.version)
                    }
                }
                for await r in group {
                    if let r { group.cancelAll(); return r }
                }
                return nil
            }
            if let found {
                config.host = found.0
                config.version = found.1
                note("Found the blaster at \(found.0)")
                connect()
            } else {
                state = .failed("Found \(hosts.count) Tuya device\(hosts.count == 1 ? "" : "s") but none took the blaster's key. If you re-paired it, refresh the key.")
            }
        }
    }

    func setHost(_ host: String) {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return }
        disconnect()
        config.host = h
        config.version = nil
        connect()
    }

    // MARK: - Incoming

    func receive(_ dps: [String: JSONValue]) {
        guard !dps.isEmpty else { return }
        seenDPs.formUnion(dps.keys)
        let summary = dps.keys.sorted().map { k -> String in
            let v = dps[k]?.display ?? ""
            return "\(k)=\(v.count > 40 ? String(v.prefix(40)) + "…" : v)"
        }.joined(separator: ", ")
        note("← \(summary)")

        guard var s = learning, s.phase == .waiting || s.phase == .starting,
              let got = IRCommand.learned(in: dps) else { return }
        if config.forced == nil, config.detected != got.format {
            config.detected = got.format
            note("Switched command format to \(got.format.title)")
        }
        setCode(got.code, remoteID: s.remoteID, keyID: s.keyID)
        s.phase = .captured(IRPulses.pulses(got.code)?.count ?? 0)
        learning = s
        learnTimeout?.cancel()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { try? await link?.set(IRCommand.studyExit(format)) }
    }

    // MARK: - Buttons

    func key(_ remoteID: UUID, _ keyID: String) -> IRKey? {
        remotes.first { $0.id == remoteID }?.key(keyID)
    }

    func tap(_ remoteID: UUID, _ keyID: String) {
        guard learning == nil, let k = key(remoteID, keyID) else { return }
        if learnMode || k.activeCode == nil {
            startLearn(remoteID: remoteID, keyID: keyID)
            return
        }
        haptic.impactOccurred()
        if let code = k.activeCode { Task { await send(code, label: k.label) } }
    }

    func send(_ code: String, label: String) async {
        do {
            var l = try await ensureLink()
            do {
                try await l.set(IRCommand.send(code, format))
            } catch {
                // The socket went stale while the app sat idle: reconnect once and resend.
                link = nil
                await l.close()
                l = try await ensureLink()
                try await l.set(IRCommand.send(code, format))
            }
            note("→ \(label)")
        } catch {
            show(error.localizedDescription)
        }
    }

    func setCode(_ code: String?, remoteID: UUID, keyID: String) {
        guard let r = remotes.firstIndex(where: { $0.id == remoteID }),
              let k = remotes[r].keys.firstIndex(where: { $0.id == keyID }) else { return }
        remotes[r].keys[k].code = code
    }

    // MARK: - Learning

    func startLearn(remoteID: UUID, keyID: String) {
        guard let r = remotes.first(where: { $0.id == remoteID }), let k = r.key(keyID) else { return }
        learnTimeout?.cancel()
        // Keep the same session id so the sheet stays up when learning again.
        var s = learning ?? LearnSession(remoteID: remoteID, keyID: keyID, label: k.label, remoteName: r.name)
        s.remoteID = remoteID
        s.keyID = keyID
        s.label = k.label
        s.remoteName = r.name
        s.phase = .starting
        learning = s
        Task {
            do {
                let l = try await ensureLink()
                try await l.set(IRCommand.studyExit(format))
                try await Task.sleep(nanoseconds: 150_000_000)
                try await l.set(IRCommand.study(format))
                note("Learning \(k.label)…")
                if learning?.phase == .starting { learning?.phase = .waiting }
                armLearnTimeout()
            } catch {
                if learning != nil { learning?.phase = .failed(error.localizedDescription) }
            }
        }
    }

    private func armLearnTimeout() {
        learnTimeout?.cancel()
        learnTimeout = Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, learning?.phase == .waiting else { return }
            learning?.phase = .failed("Nothing came in. Hold the remote 5 to 10 cm from the blaster, aim at it, and press once firmly.")
            try? await link?.set(IRCommand.studyExit(format))
        }
    }

    func learnAgain() {
        guard let s = learning else { return }
        startLearn(remoteID: s.remoteID, keyID: s.keyID)
    }

    func endLearn() {
        learnTimeout?.cancel()
        if let s = learning, s.phase == .waiting || s.phase == .starting {
            Task { try? await link?.set(IRCommand.studyExit(format)) }
        }
        learning = nil
    }

    func testLearned() {
        guard let s = learning, let k = key(s.remoteID, s.keyID), let code = k.activeCode else { return }
        haptic.impactOccurred()
        Task { await send(code, label: k.label) }
    }

    // MARK: - Remotes

    func add(_ r: Remote) {
        remotes.append(r)
        selected = r.id
    }

    func rename(_ id: UUID, to name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let i = remotes.firstIndex(where: { $0.id == id }) else { return }
        remotes[i].name = n
    }

    func delete(_ id: UUID) {
        remotes.removeAll { $0.id == id }
        if selected == id { selected = remotes.first?.id }
    }

    func move(_ id: UUID, by offset: Int) {
        guard let i = remotes.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard remotes.indices.contains(j) else { return }
        remotes.swapAt(i, j)
    }

    func addCustomKey(_ remoteID: UUID, label: String, symbol: String?) {
        guard let i = remotes.firstIndex(where: { $0.id == remoteID }) else { return }
        let l = label.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty else { return }
        let id = "k\(Int(Date().timeIntervalSince1970 * 1000))"
        remotes[i].keys.append(IRKey(id, l, symbol))
        startLearn(remoteID: remoteID, keyID: id)
    }

    func removeKey(_ remoteID: UUID, _ keyID: String) {
        guard let i = remotes.firstIndex(where: { $0.id == remoteID }) else { return }
        remotes[i].keys.removeAll { $0.id == keyID }
    }

    func renameKey(_ remoteID: UUID, _ keyID: String, to label: String) {
        let l = label.trimmingCharacters(in: .whitespaces)
        guard !l.isEmpty, let i = remotes.firstIndex(where: { $0.id == remoteID }),
              let k = remotes[i].keys.firstIndex(where: { $0.id == keyID }) else { return }
        remotes[i].keys[k].label = l
    }

    // MARK: - Backup

    func exportURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Redshift remotes.json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(remotes), (try? d.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    func importRemotes(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Remote].self, from: d) else {
            show("That file isn't an Redshift backup.")
            return
        }
        for r in list {
            if let i = remotes.firstIndex(where: { $0.id == r.id }) { remotes[i] = r } else { remotes.append(r) }
        }
        show("Imported \(list.count) remote\(list.count == 1 ? "" : "s")")
    }

    // MARK: - Messages

    func show(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }

    func note(_ text: String) {
        log.append(LogLine(text: text))
        if log.count > 200 { log.removeFirst(log.count - 200) }
    }
}
