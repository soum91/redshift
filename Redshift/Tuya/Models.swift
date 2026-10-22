import Foundation

struct DeviceInfo: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var category: String
    var productName: String
    var online: Bool
    var localKey: String?
    /// Paired through a hub (Zigbee/BLE gateway) rather than on Wi-Fi itself.
    var isSub: Bool = false

    static func parse(_ d: [String: Any]) -> DeviceInfo? {
        guard let id = d["id"] as? String else { return nil }
        return DeviceInfo(id: id,
                          name: (d["name"] as? String) ?? "Device",
                          category: (d["category"] as? String) ?? "",
                          productName: (d["product_name"] as? String) ?? (d["productName"] as? String) ?? "",
                          online: (d["online"] as? Bool) ?? ((d["online"] as? NSNumber)?.boolValue ?? true),
                          localKey: (d["local_key"] as? String) ?? (d["localKey"] as? String),
                          isSub: (d["sub"] as? Bool) ?? ((d["sub"] as? NSNumber)?.boolValue ?? false))
    }

    /// "wnykq" is Tuya's universal remote (IR blaster) category.
    var isBlaster: Bool {
        let p = productName.lowercased()
        return category == "wnykq" || category == "wnyk" || p.contains("remote") || p.contains("ir blaster")
    }

    var hasKey: Bool { !(localKey ?? "").isEmpty }
}

/// Plain JSON files in Application Support.
enum FileStore {
    static let dir: URL = {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: d)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let d = try? JSONEncoder().encode(value) else { return }
        try? d.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    static func remove(_ name: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }
}

enum TokenStore {
    static func load() -> TuyaToken? { FileStore.read(TuyaToken.self, "token.json") }
    static func save(_ t: TuyaToken) { FileStore.write(t, "token.json") }
    static func clear() { FileStore.remove("token.json") }
}

/// Everything needed to reach the blaster on Wi-Fi.
struct BlasterConfig: Codable, Equatable {
    var devId: String?
    var name: String?
    var localKey: String?
    var host: String?
    var version: Double?
    /// What the blaster turned out to speak.
    var detected: IRFormat?
    /// Set by hand in Settings when detection gets it wrong.
    var forced: IRFormat?

    var hasKey: Bool { !(devId ?? "").isEmpty && !(localKey ?? "").isEmpty }
    var isReady: Bool { hasKey && !(host ?? "").isEmpty }
    var format: IRFormat { forced ?? detected ?? .classic }

    static var stored: BlasterConfig {
        get { FileStore.read(BlasterConfig.self, "blaster.json") ?? BlasterConfig() }
        set { FileStore.write(newValue, "blaster.json") }
    }
}
