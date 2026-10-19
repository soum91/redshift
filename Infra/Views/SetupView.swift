import SwiftUI

struct SetupView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            Group {
                if store.config.hasKey {
                    FindBlasterView()
                } else if store.token != nil {
                    BlasterPickerView()
                } else {
                    LoginView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                NavigationLink("I have the key") { ManualKeyView() }
                            }
                        }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

struct BlasterPickerView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ZStack {
            Theme.background(Theme.accent)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pick your IR blaster").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Infra saves its local key and talks to it over Wi-Fi from here on.")
                        .foregroundStyle(.secondary)

                    if store.loadingDevices {
                        HStack { ProgressView(); Text("Loading your devices…").foregroundStyle(.secondary) }
                            .padding(.top, 20)
                    }
                    if let e = store.setupError {
                        Text(e).font(.footnote).foregroundStyle(Theme.accent)
                    }

                    let blasters = store.devices.filter(\.isBlaster)
                    let others = store.devices.filter { !$0.isBlaster }
                    if !blasters.isEmpty {
                        SectionTitle(text: "IR blasters").padding(.top, 8)
                        ForEach(blasters) { row($0) }
                    }
                    if !others.isEmpty {
                        SectionTitle(text: blasters.isEmpty ? "Your devices" : "Everything else").padding(.top, 8)
                        ForEach(others) { row($0) }
                    }

                    HStack {
                        Button("Reload") { Task { await store.loadDevices() } }
                        Spacer()
                        Button("Sign out", role: .destructive) { store.signOutCloud() }
                    }
                    .font(.footnote)
                    .padding(.top, 8)
                }
                .padding(20)
            }
        }
        .task { if store.devices.isEmpty { await store.loadDevices() } }
    }

    private func row(_ d: DeviceInfo) -> some View {
        Button { store.choose(d) } label: {
            HStack(spacing: 14) {
                Image(systemName: d.isBlaster ? "dot.radiowaves.right" : "cpu")
                    .font(.title3)
                    .foregroundStyle(d.isBlaster ? Theme.accent : .secondary)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).fontWeight(.semibold)
                    Text(d.productName.isEmpty ? d.category : d.productName)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !d.hasKey {
                    Text("no key").font(.caption2).foregroundStyle(.secondary)
                } else if !d.online {
                    Text("offline").font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

struct ManualKeyView: View {
    @EnvironmentObject var store: Store
    @State private var devId = ""
    @State private var key = ""
    @State private var name = "IR blaster"

    var body: some View {
        Form {
            Section {
                TextField("Device ID", text: $devId)
                TextField("Local key", text: $key)
                TextField("Name", text: $name)
            } footer: {
                Text("From tinytuya's wizard, Home Assistant, or Tuya's IoT platform. The local key is 16 characters.")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(.body, design: .monospaced))

            Button("Save and find on Wi-Fi") {
                store.setBlaster(devId: devId.trimmingCharacters(in: .whitespaces),
                                 key: key.trimmingCharacters(in: .whitespaces),
                                 name: name)
            }
            .disabled(devId.trimmingCharacters(in: .whitespaces).isEmpty || key.trimmingCharacters(in: .whitespaces).count < 8)
        }
        .navigationTitle("Enter key")
    }
}

struct FindBlasterView: View {
    @EnvironmentObject var store: Store
    @State private var ip = ""

    var body: some View {
        ZStack {
            Theme.background(Theme.accent)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Finding \(store.config.name ?? "your blaster")")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Your phone has to be on the same Wi-Fi as the blaster. Allow Local Network when iOS asks.")
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        if store.state.isBusy { ProgressView() }
                        Text(store.state.text).font(.callout)
                    }
                    .card()

                    Button { store.findOnWiFi() } label: {
                        Text("Scan again").fontWeight(.semibold)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.black)
                    }
                    .disabled(store.state.isBusy)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "Or type its IP")
                        Text("Your router's device list shows it, usually as something like ESP or a Tuya name.")
                            .font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            TextField("192.168.1.50", text: $ip)
                                .keyboardType(.decimalPad)
                                .font(.system(.body, design: .monospaced))
                                .padding(12)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                            Button("Connect") { store.setHost(ip) }
                                .disabled(ip.split(separator: ".").count != 4)
                        }
                    }
                    .card()

                    Button("Use a different device", role: .destructive) { store.forgetBlaster() }
                        .font(.footnote)
                }
                .padding(20)
            }
        }
    }
}
