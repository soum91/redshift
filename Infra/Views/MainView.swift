import SwiftUI

struct MainView: View {
    @EnvironmentObject var store: Store
    @State private var showSettings = false
    @State private var renaming: Remote?
    @State private var renameText = ""
    @State private var deleting: Remote?

    var body: some View {
        let remote = store.current
        let accent = remote?.kind.accent ?? Theme.accent
        ZStack(alignment: .bottom) {
            Theme.background(accent).animation(.easeInOut(duration: 0.35), value: remote?.id)

            VStack(spacing: 0) {
                header
                chips
                ScrollView {
                    if let remote {
                        VStack(spacing: 18) {
                            if store.learnMode { learnBanner(remote) }
                            RemoteScreen(remote: remote)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 60)
                    } else {
                        Text("No remotes yet. Tap + to add one.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 80)
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let t = store.toast {
                Text(t)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { store.toast = nil }
            }
        }
        .animation(.snappy, value: store.toast)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: Binding(get: { store.learning }, set: { if $0 == nil { store.endLearn() } })) { s in
            LearnSheet(fallback: s)
                .presentationDetents([.height(380)])
                .presentationBackground(.ultraThinMaterial)
        }
        .alert("Rename remote", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let r = renaming { store.rename(r.id, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "remote")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let d = deleting { store.delete(d.id) }
                deleting = nil
            }
        } message: {
            Text("Its learned codes go with it. Export a backup in Settings first if you might want them.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Button { store.reconnect() } label: {
                HStack(spacing: 8) {
                    Circle().fill(dotColor).frame(width: 8, height: 8)
                    Text(statusText).font(.footnote.weight(.medium)).lineLimit(1)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.card, in: Capsule())
                .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Button {
                withAnimation(.snappy) { store.learnMode.toggle() }
            } label: {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(store.learnMode ? Theme.accent : Theme.card, in: Circle())
                    .foregroundStyle(store.learnMode ? Color.black : Color.white)
            }
            .accessibilityLabel("Learn mode")
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var statusText: String {
        switch store.state {
        case .connected: return store.config.name ?? "Connected"
        case .failed: return "Offline · tap to retry"
        default: return store.state.text
        }
    }

    private var dotColor: Color {
        switch store.state {
        case .connected: return .green
        case .failed: return .red
        case .off: return .gray
        default: return .yellow
        }
    }

    // MARK: Remote chips

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(store.remotes) { r in
                    let on = r.id == store.current?.id
                    Button {
                        withAnimation(.snappy) { store.selected = r.id }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: r.kind.symbol).font(.system(size: 13, weight: .semibold))
                            Text(r.name).font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(on ? r.kind.accent.opacity(0.9) : Theme.card, in: Capsule())
                        .foregroundStyle(on ? Color.black : Color.white.opacity(0.85))
                    }
                    .contextMenu {
                        Button { renameText = r.name; renaming = r } label: { Label("Rename", systemImage: "pencil") }
                        Button { store.move(r.id, by: -1) } label: { Label("Move left", systemImage: "arrow.left") }
                        Button { store.move(r.id, by: 1) } label: { Label("Move right", systemImage: "arrow.right") }
                        Button(role: .destructive) { deleting = r } label: { Label("Delete", systemImage: "trash") }
                    }
                }
                Menu {
                    Button { store.add(Templates.sonyTV()) } label: { Label("Sony TV (works right away)", systemImage: "tv") }
                    Button { store.add(Templates.blankTV()) } label: { Label("Other TV (learn buttons)", systemImage: "tv") }
                    Button { store.add(Templates.vizioSoundbar(name: "Sound bar")) } label: { Label("Sound bar", systemImage: "hifispeaker.fill") }
                    Button { store.add(Templates.delonghiHeater(name: "Heater")) } label: { Label("Heater", systemImage: "flame.fill") }
                    Button { store.add(Templates.custom()) } label: { Label("Anything else (custom)", systemImage: "square.grid.2x2.fill") }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 38, height: 36)
                        .background(Theme.card, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func learnBanner(_ r: Remote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Learn mode").font(.headline)
                Spacer()
                Button("Done") { withAnimation(.snappy) { store.learnMode = false } }.fontWeight(.semibold)
            }
            Text("Tap any button, then press the same button on the real remote while aiming it at the blaster.")
                .font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                legend(.green, "Learned")
                if r.keys.contains(where: { $0.builtin != nil }) { legend(Color(red: 0.4, green: 0.65, blue: 1), "Built-in") }
                legend(.orange, "Not set")
            }
            .font(.caption)
        }
        .card()
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(t).foregroundStyle(.secondary)
        }
    }
}

struct LearnSheet: View {
    @EnvironmentObject var store: Store
    let fallback: LearnSession
    @State private var pulse = false

    var body: some View {
        let s = store.learning ?? fallback
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Learn “\(s.label)”").font(.title3.bold())
                Text(s.remoteName).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Spacer(minLength: 0)

            switch s.phase {
            case .starting:
                ProgressView().controlSize(.large)
                Text("Putting the blaster in learning mode…").foregroundStyle(.secondary)
            case .waiting:
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .scaleEffect(pulse ? 1.12 : 0.92)
                    .opacity(pulse ? 1 : 0.6)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
                    }
                Text("Aim the real remote at the blaster from about 10 cm and press **\(s.label)** once.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            case .captured(let n):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)
                Text("Got it\(n > 0 ? " · \(n) pulses" : "")").font(.headline)
                HStack(spacing: 12) {
                    sheetButton("Test it", filled: true) { store.testLearned() }
                    sheetButton("Learn again", filled: false) { store.learnAgain() }
                }
            case .failed(let e):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.orange)
                Text(e).multilineTextAlignment(.center).foregroundStyle(.secondary).font(.callout)
                sheetButton("Try again", filled: true) { store.learnAgain() }
            }

            Spacer(minLength: 0)

            Button(s.phase == .waiting || s.phase == .starting ? "Cancel" : "Done") { store.endLearn() }
                .fontWeight(.semibold)
                .padding(.bottom, 8)
        }
        .padding(24)
    }

    private func sheetButton(_ title: String, filled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).fontWeight(.semibold)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(filled ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(filled ? Color.black : Color.white)
        }
    }
}
