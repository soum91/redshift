import SwiftUI

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Fires on touch down, then repeats while held, like a real volume button.
struct RepeatPress: ViewModifier {
    let action: () -> Void
    @State private var pressed = false
    @State private var timer: Timer?

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.9 : 1)
            .brightness(pressed ? 0.12 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        action()
                        timer?.invalidate()
                        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
                            Task { @MainActor in
                                guard pressed else { return }
                                timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { _ in
                                    Task { @MainActor in action() }
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        timer?.invalidate()
                        timer = nil
                    }
            )
    }
}

/// One remote button. Untaught buttons look dim; tapping them starts learning.
struct KeyButton: View {
    @EnvironmentObject var store: Store
    let remote: Remote
    let id: String
    var size: CGFloat = 60
    var tint: Color? = nil
    var bare = false
    var wide = false
    var repeats = false
    var caption = false
    var onRename: ((IRKey) -> Void)? = nil
    var onDelete: ((IRKey) -> Void)? = nil

    var body: some View {
        if let k = remote.key(id) {
            VStack(spacing: 6) {
                if repeats {
                    face(k).modifier(RepeatPress { store.tap(remote.id, id) })
                } else {
                    Button { store.tap(remote.id, id) } label: { face(k) }
                        .buttonStyle(PressStyle())
                        .contextMenu { menu(k) }
                }
                if caption {
                    Text(k.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .accessibilityLabel(k.label)
        }
    }

    @ViewBuilder
    private func face(_ k: IRKey) -> some View {
        let radius = wide ? 18 : size / 2
        ZStack {
            if !bare {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint.map { AnyShapeStyle($0.gradient) } ?? AnyShapeStyle(Color.white.opacity(0.08)))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(tint == nil ? 0.08 : 0.18))
            }
            if let s = k.symbol {
                Image(systemName: s).font(.system(size: size * 0.34, weight: .semibold))
            } else {
                Text(k.label)
                    .font(.system(size: k.label.count > 3 ? max(size * 0.22, 12) : size * 0.32, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
            }
        }
        .frame(width: wide ? nil : size, height: size)
        .frame(maxWidth: wide ? .infinity : nil)
        .contentShape(Rectangle())
        .foregroundStyle(tint != nil ? Color.white : Color.white.opacity(k.isReady ? 0.92 : 0.32))
        .overlay(alignment: .topTrailing) {
            if store.learnMode { badge(k).offset(x: bare ? -4 : 2, y: bare ? 4 : -2) }
        }
    }

    @ViewBuilder
    private func badge(_ k: IRKey) -> some View {
        Circle()
            .fill(k.isLearned ? Color.green : (k.builtin != nil ? Color(red: 0.4, green: 0.65, blue: 1) : Color.orange))
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1.5))
    }

    @ViewBuilder
    private func menu(_ k: IRKey) -> some View {
        Button { store.startLearn(remoteID: remote.id, keyID: id) } label: {
            Label(k.isLearned ? "Learn again" : "Learn from remote", systemImage: "dot.radiowaves.left.and.right")
        }
        if k.isLearned {
            Button(role: .destructive) { store.setCode(nil, remoteID: remote.id, keyID: id) } label: {
                Label(k.builtin != nil ? "Go back to built-in code" : "Forget learned code", systemImage: "arrow.uturn.backward")
            }
        }
        if let onRename {
            Button { onRename(k) } label: { Label("Rename", systemImage: "pencil") }
        }
        if let onDelete {
            Button(role: .destructive) { onDelete(k) } label: { Label("Delete button", systemImage: "trash") }
        }
    }
}

/// Tall capsule with up and down, for volume and channel.
struct Rocker: View {
    let remote: Remote
    let up: String
    let down: String
    let title: String
    var height: CGFloat = 180

    var body: some View {
        VStack(spacing: 0) {
            KeyButton(remote: remote, id: up, size: 62, bare: true, repeats: true)
            Spacer(minLength: 0)
            Text(title).font(.system(size: 12, weight: .bold)).tracking(1).foregroundStyle(.white.opacity(0.45))
            Spacer(minLength: 0)
            KeyButton(remote: remote, id: down, size: 62, bare: true, repeats: true)
        }
        .frame(width: 72, height: height)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08)))
    }
}

/// Horizontal minus / plus pair with a title, for bass, treble and temperature.
struct PairRow: View {
    let remote: Remote
    let title: String
    let down: String
    let up: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            KeyButton(remote: remote, id: down, size: 50, repeats: true)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 13, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 0)
            KeyButton(remote: remote, id: up, size: 50, repeats: true)
        }
        .padding(8)
        .background(Color.white.opacity(0.05), in: Capsule())
    }
}
