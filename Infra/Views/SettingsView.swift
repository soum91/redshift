import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var ip = ""
    @State private var importing = false
    @State private var confirmForget = false
    @State private var refreshing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Blaster") {
                    row("Name", store.config.name ?? "–")
                    row("Status", store.state.text)
                    row("IP", store.config.host ?? "–")
                    if let v = store.config.version { row("Protocol", String(format: "%.1f", v)) }
                    row("Device ID", store.config.devId ?? "–", mono: true)
                    Button("Reconnect") { store.reconnect() }
                    Button("Find it on Wi-Fi again") { store.findOnWiFi() }
                    HStack {
                        TextField("Set IP by hand", text: $ip)
                            .keyboardType(.decimalPad)
                            .font(.system(.body, design: .monospaced))
                        Button("Use") { store.setHost(ip); ip = "" }
                            .disabled(ip.split(separator: ".").count != 4)
                    }
                }

                Section {
                    Picker("Command format", selection: Binding(get: { store.config.forced },
                                                                set: { store.config.forced = $0 })) {
                        Text("Auto (\(store.config.detected?.title ?? "not detected yet"))").tag(IRFormat?.none)
                        ForEach(IRFormat.allCases) { f in
                            Text(f.title).tag(IRFormat?.some(f))
                        }
                    }
                } header: {
                    Text("IR commands")
                } footer: {
                    Text("Older blasters (S06, UFO-R11 and similar) use DP 201. Newer ones use DP 1 to 13. Auto picks it up when you connect and corrects itself the first time you learn a button. Only change this if buttons do nothing.")
                }

                Section {
                    if store.token != nil {
                        Button {
                            refreshing = true
                            Task { await store.refreshKey(); refreshing = false }
                        } label: {
                            HStack {
                                Text("Refresh local key from Smart Life")
                                if refreshing { Spacer(); ProgressView() }
                            }
                        }
                        Button("Sign out of Smart Life") { store.signOutCloud() }
                    } else {
                        NavigationLink("Sign in to Smart Life") { LoginView() }
                    }
                    Button("Use a different blaster", role: .destructive) { confirmForget = true }
                } header: {
                    Text("Local key")
                } footer: {
                    Text("Smart Life is only used to fetch the key. Every button press goes straight to the blaster on your Wi-Fi, even with the internet down. If you re-pair the blaster in Smart Life its key changes, so refresh it here.")
                }

                Section("Remotes") {
                    if let url = store.exportURL() {
                        ShareLink(item: url) { Label("Export backup", systemImage: "square.and.arrow.up") }
                    }
                    Button { importing = true } label: { Label("Import backup", systemImage: "square.and.arrow.down") }
                }

                Section {
                    NavigationLink("Activity log") { LogView() }
                } footer: {
                    Text("Shows every raw value the blaster reports. Screenshot it if something's off.")
                }

                Section {
                    row("Version", (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "?")
                } footer: {
                    Text("Talks to the blaster with Tuya's local protocol. Unofficial, not affiliated with Tuya.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { store.importRemotes(from: url) }
            }
            .confirmationDialog("Switch blasters?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Switch", role: .destructive) {
                    store.forgetBlaster()
                    dismiss()
                }
            } message: {
                Text("Your remotes and learned codes stay. You'll pick the blaster and find it on Wi-Fi again.")
            }
        }
    }

    private func row(_ title: String, _ value: String, mono: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(mono ? .system(.footnote, design: .monospaced) : .body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct LogView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        List(store.log.reversed()) { line in
            VStack(alignment: .leading, spacing: 2) {
                Text(line.time.formatted(date: .omitted, time: .standard))
                    .font(.caption2).foregroundStyle(.secondary)
                Text(line.text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .overlay {
            if store.log.isEmpty { Text("Nothing yet.").foregroundStyle(.secondary) }
        }
        .navigationTitle("Activity log")
        .navigationBarTitleDisplayMode(.inline)
    }
}
