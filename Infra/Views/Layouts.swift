import SwiftUI

private let powerRed = Color(red: 0.92, green: 0.22, blue: 0.24)

struct RemoteScreen: View {
    let remote: Remote

    var body: some View {
        switch remote.kind {
        case .tv: TVLayout(remote: remote)
        case .soundbar: SoundbarLayout(remote: remote)
        case .heater: HeaterLayout(remote: remote)
        case .custom: CustomLayout(remote: remote)
        }
    }
}

// MARK: - TV

struct TVLayout: View {
    let remote: Remote
    @State private var showNumbers = false

    var body: some View {
        VStack(spacing: 26) {
            HStack {
                KeyButton(remote: remote, id: "power", size: 58, tint: powerRed)
                Spacer()
                KeyButton(remote: remote, id: "netflix", size: 58, tint: Color(red: 0.75, green: 0.05, blue: 0.08))
                KeyButton(remote: remote, id: "input", size: 58)
            }

            DPad(remote: remote)

            HStack(spacing: 22) {
                KeyButton(remote: remote, id: "back", size: 56)
                KeyButton(remote: remote, id: "home", size: 56)
                KeyButton(remote: remote, id: "options", size: 56)
            }

            HStack(alignment: .center) {
                Rocker(remote: remote, up: "volUp", down: "volDown", title: "VOL")
                Spacer()
                VStack(spacing: 18) {
                    KeyButton(remote: remote, id: "mute", size: 58)
                    KeyButton(remote: remote, id: "guide", size: 58)
                }
                Spacer()
                Rocker(remote: remote, up: "chUp", down: "chDown", title: "CH")
            }
            .padding(.horizontal, 12)

            HStack(spacing: 22) {
                KeyButton(remote: remote, id: "play", size: 52)
                KeyButton(remote: remote, id: "pause", size: 52)
            }

            VStack(spacing: 14) {
                Button {
                    withAnimation(.snappy) { showNumbers.toggle() }
                } label: {
                    HStack {
                        Text("Numbers").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(showNumbers ? 180 : 0))
                    }
                    .foregroundStyle(.white.opacity(0.7))
                }
                if showNumbers {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                        ForEach(["n1", "n2", "n3", "n4", "n5", "n6", "n7", "n8", "n9"], id: \.self) {
                            KeyButton(remote: remote, id: $0, size: 58)
                        }
                        Color.clear.frame(height: 58)
                        KeyButton(remote: remote, id: "n0", size: 58)
                    }
                }
            }
            .card()
        }
    }
}

struct DPad: View {
    let remote: Remote

    var body: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.07))
            Circle().stroke(Color.white.opacity(0.08))
            VStack {
                KeyButton(remote: remote, id: "up", size: 64, bare: true)
                Spacer()
                KeyButton(remote: remote, id: "down", size: 64, bare: true)
            }
            .padding(.vertical, 6)
            HStack {
                KeyButton(remote: remote, id: "left", size: 64, bare: true)
                Spacer()
                KeyButton(remote: remote, id: "right", size: 64, bare: true)
            }
            .padding(.horizontal, 6)
            KeyButton(remote: remote, id: "ok", size: 92, tint: remote.kind.accent.opacity(0.55))
        }
        .frame(width: 250, height: 250)
    }
}

// MARK: - Sound bar

struct SoundbarLayout: View {
    let remote: Remote

    var body: some View {
        VStack(spacing: 26) {
            HStack {
                KeyButton(remote: remote, id: "power", size: 58, tint: powerRed)
                Spacer()
                KeyButton(remote: remote, id: "bluetooth", size: 58)
                KeyButton(remote: remote, id: "input", size: 58)
            }

            HStack(alignment: .center) {
                Rocker(remote: remote, up: "volUp", down: "volDown", title: "VOL", height: 210)
                Spacer()
                VStack(spacing: 18) {
                    KeyButton(remote: remote, id: "mute", size: 58, caption: true)
                    KeyButton(remote: remote, id: "eq", size: 58, caption: true)
                    KeyButton(remote: remote, id: "menu", size: 58, caption: true)
                }
                Spacer()
                Color.clear.frame(width: 72)
            }
            .padding(.horizontal, 12)

            VStack(spacing: 12) {
                PairRow(remote: remote, title: "BASS", down: "bassDown", up: "bassUp")
                PairRow(remote: remote, title: "TREBLE", down: "trebleDown", up: "trebleUp")
            }

            HStack(spacing: 26) {
                KeyButton(remote: remote, id: "prev", size: 54)
                KeyButton(remote: remote, id: "playPause", size: 66, tint: remote.kind.accent.opacity(0.5))
                KeyButton(remote: remote, id: "next", size: 54)
            }
        }
    }
}

// MARK: - Heater

struct HeaterLayout: View {
    let remote: Remote

    var body: some View {
        VStack(spacing: 28) {
            KeyButton(remote: remote, id: "power", size: 124,
                      tint: Color(red: 1.0, green: 0.42, blue: 0.16), caption: false)
                .shadow(color: Color.orange.opacity(0.45), radius: 24)
                .padding(.top, 10)

            PairRow(remote: remote, title: "TEMP", down: "tempDown", up: "tempUp", symbol: "thermometer.medium")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 22) {
                ForEach(["mode", "fan", "oscillate", "timer", "eco", "light"], id: \.self) {
                    KeyButton(remote: remote, id: $0, size: 64, caption: true)
                }
            }
            .card()

            Text("IR only goes one way, so Infra can't see whether the heater is on. Check the heater's own display.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Custom

struct CustomLayout: View {
    @EnvironmentObject var store: Store
    let remote: Remote
    @State private var adding = false
    @State private var newLabel = ""
    @State private var renaming: IRKey?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 18) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 22) {
                ForEach(remote.keys) { k in
                    KeyButton(remote: remote, id: k.id, size: 68,
                              tint: k.id == "power" ? powerRed : nil, caption: true,
                              onRename: { renaming = $0; renameText = $0.label },
                              onDelete: { store.removeKey(remote.id, $0.id) })
                }
                Button { newLabel = ""; adding = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 68, height: 68)
                            .overlay(Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                        Text("Add button").font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(PressStyle())
            }
            Text("Long-press a button to rename, re-learn or delete it.")
                .font(.footnote).foregroundStyle(.white.opacity(0.4))
        }
        .alert("New button", isPresented: $adding) {
            TextField("Name, like Fan speed", text: $newLabel)
            Button("Add and learn") { store.addCustomKey(remote.id, label: newLabel, symbol: nil) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Then point the real remote at the blaster and press the button.")
        }
        .alert("Rename button", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let k = renaming { store.renameKey(remote.id, k.id, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}
