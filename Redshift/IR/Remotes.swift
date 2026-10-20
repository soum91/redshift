import Foundation
import SwiftUI

enum RemoteKind: String, Codable, CaseIterable {
    case tv, soundbar, heater, custom

    var accent: Color {
        switch self {
        case .tv: return Color(red: 0.36, green: 0.62, blue: 1.0)
        case .soundbar: return Color(red: 0.70, green: 0.50, blue: 1.0)
        case .heater: return Color(red: 1.0, green: 0.52, blue: 0.24)
        case .custom: return Color(red: 0.30, green: 0.85, blue: 0.70)
        }
    }

    var symbol: String {
        switch self {
        case .tv: return "tv"
        case .soundbar: return "hifispeaker.fill"
        case .heater: return "flame.fill"
        case .custom: return "square.grid.2x2.fill"
        }
    }
}

struct IRKey: Codable, Identifiable, Hashable {
    var id: String
    var label: String
    var symbol: String?
    /// Learned from the real remote. Wins over the built-in code.
    var code: String?
    /// Generated from a known protocol (Sony TV), so it works before learning anything.
    var builtin: String?

    var activeCode: String? { code ?? builtin }
    var isLearned: Bool { code != nil }
    var isReady: Bool { activeCode != nil }

    init(_ id: String, _ label: String, _ symbol: String? = nil, builtin: String? = nil) {
        self.id = id
        self.label = label
        self.symbol = symbol
        self.builtin = builtin
    }
}

struct Remote: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var kind: RemoteKind
    var keys: [IRKey]

    func key(_ id: String) -> IRKey? { keys.first { $0.id == id } }
    var readyCount: Int { keys.filter(\.isReady).count }
}

// MARK: - Templates

enum Templates {
    static func sonyTV(name: String = "Sony TV") -> Remote {
        var keys: [IRKey] = [
            IRKey("power", "Power", "power", builtin: Sony.tv(21)),
            IRKey("input", "Input", "rectangle.portrait.and.arrow.forward", builtin: Sony.tv(37)),
            IRKey("volUp", "Volume up", "plus", builtin: Sony.tv(18)),
            IRKey("volDown", "Volume down", "minus", builtin: Sony.tv(19)),
            IRKey("mute", "Mute", "speaker.slash.fill", builtin: Sony.tv(20)),
            IRKey("chUp", "Channel up", "chevron.up", builtin: Sony.tv(16)),
            IRKey("chDown", "Channel down", "chevron.down", builtin: Sony.tv(17)),
            IRKey("up", "Up", "chevron.up", builtin: Sony.tv(116)),
            IRKey("down", "Down", "chevron.down", builtin: Sony.tv(117)),
            IRKey("left", "Left", "chevron.left", builtin: Sony.tv(52)),
            IRKey("right", "Right", "chevron.right", builtin: Sony.tv(51)),
            IRKey("ok", "OK", nil, builtin: Sony.tv(101)),
            IRKey("home", "Home", "house.fill", builtin: Sony.tv(96)),
            IRKey("back", "Back", "arrow.uturn.backward", builtin: Sony.tv15(0x97, 35)),
            IRKey("options", "Options", "ellipsis", builtin: Sony.tv15(0x97, 54)),
            IRKey("guide", "Guide", "list.bullet.rectangle", builtin: Sony.tv15(0xA4, 91)),
            IRKey("play", "Play", "play.fill", builtin: Sony.tv15(0x97, 26)),
            IRKey("pause", "Pause", "pause.fill", builtin: Sony.tv15(0x97, 25)),
            IRKey("netflix", "Netflix", nil, builtin: Sony.tv15(0x1A, 124)),
        ]
        for n in 1...9 { keys.append(IRKey("n\(n)", "\(n)", nil, builtin: Sony.tv(n - 1))) }
        keys.append(IRKey("n0", "0", nil, builtin: Sony.tv(9)))
        return Remote(name: name, kind: .tv, keys: keys)
    }

    static func blankTV(name: String = "TV") -> Remote {
        var r = sonyTV(name: name)
        for i in r.keys.indices { r.keys[i].builtin = nil }
        return r
    }

    static func vizioSoundbar(name: String = "Vizio sound bar") -> Remote {
        Remote(name: name, kind: .soundbar, keys: [
            IRKey("power", "Power", "power"),
            IRKey("input", "Input", "rectangle.portrait.and.arrow.forward"),
            IRKey("bluetooth", "Bluetooth", "dot.radiowaves.left.and.right"),
            IRKey("volUp", "Volume up", "plus"),
            IRKey("volDown", "Volume down", "minus"),
            IRKey("mute", "Mute", "speaker.slash.fill"),
            IRKey("bassUp", "Bass up", "plus"),
            IRKey("bassDown", "Bass down", "minus"),
            IRKey("trebleUp", "Treble up", "plus"),
            IRKey("trebleDown", "Treble down", "minus"),
            IRKey("eq", "Sound mode", "slider.horizontal.3"),
            IRKey("menu", "Menu", "line.3.horizontal"),
            IRKey("prev", "Previous", "backward.fill"),
            IRKey("playPause", "Play/Pause", "playpause.fill"),
            IRKey("next", "Next", "forward.fill"),
        ])
    }

    static func delonghiHeater(name: String = "De'Longhi heater") -> Remote {
        Remote(name: name, kind: .heater, keys: [
            IRKey("power", "Power", "power"),
            IRKey("tempUp", "Warmer", "plus"),
            IRKey("tempDown", "Cooler", "minus"),
            IRKey("mode", "Mode", "dial.medium.fill"),
            IRKey("fan", "Fan", "fan.fill"),
            IRKey("oscillate", "Oscillate", "arrow.left.and.right"),
            IRKey("timer", "Timer", "timer"),
            IRKey("eco", "Eco", "leaf.fill"),
            IRKey("light", "Display", "lightbulb.fill"),
        ])
    }

    static func custom(name: String = "Remote") -> Remote {
        Remote(name: name, kind: .custom, keys: [IRKey("power", "Power", "power")])
    }

    static var starter: [Remote] { [sonyTV(), vizioSoundbar(), delonghiHeater()] }

    /// Symbols offered when adding a button to a custom remote.
    static let customSymbols = ["power", "plus", "minus", "chevron.up", "chevron.down", "play.fill", "pause.fill",
                                "speaker.slash.fill", "lightbulb.fill", "fan.fill", "timer", "star.fill", "moon.fill",
                                "sun.max.fill", "snowflake", "flame.fill", "arrow.clockwise", "circle.fill"]
}

enum RemoteStore {
    static func load() -> [Remote] { FileStore.read([Remote].self, "remotes.json") ?? Templates.starter }
    static func save(_ r: [Remote]) { FileStore.write(r, "remotes.json") }
}
