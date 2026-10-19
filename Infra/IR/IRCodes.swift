import Foundation

/// Tuya raw IR codes are base64 of little-endian UInt16 durations in microseconds:
/// mark, space, mark, space… always ending on a mark. Same format tinytuya uses.
enum IRPulses {
    static func base64(_ pulses: [Int]) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(pulses.count * 2)
        for p in pulses {
            let v = UInt16(clamping: p)
            bytes.append(UInt8(v & 0xff))
            bytes.append(UInt8(v >> 8))
        }
        return Data(bytes).base64EncodedString()
    }

    static func pulses(_ code: String) -> [Int]? {
        var s = code.trimmingCharacters(in: .whitespacesAndNewlines)
        // Some blasters report learned codes with a leading "1".
        if s.count % 4 == 1, s.hasPrefix("1") { s.removeFirst() }
        guard let d = Data(base64Encoded: s), !d.isEmpty, d.count % 2 == 0 else { return nil }
        let b = [UInt8](d)
        return stride(from: 0, to: b.count, by: 2).map { Int(b[$0]) | (Int(b[$0 + 1]) << 8) }
    }

    /// Cleans a learned code into plain base64 the blaster can replay.
    static func normalize(_ code: String) -> String? {
        guard let p = pulses(code), p.count >= 4 else { return nil }
        return base64(p)
    }
}

/// Sony SIRC: 2400µs header, 600µs gaps, 1200µs for a 1 and 600µs for a 0, least significant bit first.
/// 7-bit command then a 5-bit (12-bit codes) or 8-bit (15-bit codes) address. Sony TVs want it
/// three times, one frame every 45ms.
enum Sony {
    static func code(command: Int, address: Int, addressBits: Int) -> String {
        var frame: [Int] = [2400, 600]
        func add(_ value: Int, _ bits: Int) {
            for i in 0..<bits {
                frame.append((value >> i) & 1 == 1 ? 1200 : 600)
                frame.append(600)
            }
        }
        add(command, 7)
        add(address, addressBits)
        frame.removeLast()   // the last space becomes the gap to the next frame
        let length = frame.reduce(0, +)
        var all: [Int] = []
        for i in 0..<3 {
            all += frame
            if i < 2 { all.append(max(45_000 - length, 10_000)) }
        }
        return IRPulses.base64(all)
    }

    /// Standard Bravia codes: address 1, 5-bit.
    static func tv(_ command: Int) -> String { code(command: command, address: 1, addressBits: 5) }
    /// Newer Bravia keys use 15-bit codes with an 8-bit address.
    static func tv15(_ address: Int, _ command: Int) -> String { code(command: command, address: address, addressBits: 8) }
}

/// What the blaster speaks. tinytuya calls these control type 1 and 2.
enum IRFormat: String, Codable, CaseIterable, Identifiable {
    case classic, modern
    var id: String { rawValue }
    var title: String { self == .classic ? "Classic (DP 201/202)" : "Newer (DP 1–13)" }
}

enum IRCommand {
    private static func json(_ obj: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    static func send(_ code: String, _ format: IRFormat) -> [String: JSONValue] {
        switch format {
        case .classic:
            return ["201": .string(json(["control": "send_ir", "type": 0, "head": "", "key1": "1" + code]))]
        case .modern:
            return ["1": .string("study_key"), "13": .int(0), "7": .string(code)]
        }
    }

    static func mode(_ mode: String, _ format: IRFormat) -> [String: JSONValue] {
        switch format {
        case .classic: return ["201": .string(json(["control": mode]))]
        case .modern: return ["1": .string(mode)]
        }
    }

    static func study(_ f: IRFormat) -> [String: JSONValue] { mode("study", f) }
    static func studyExit(_ f: IRFormat) -> [String: JSONValue] { mode("study_exit", f) }

    /// A learned code in a status report, and which format it came in on.
    static func learned(in dps: [String: JSONValue]) -> (code: String, format: IRFormat)? {
        for (dp, f) in [("202", IRFormat.classic), ("2", IRFormat.modern)] {
            if let s = dps[dp]?.stringValue, s.count >= 8, let clean = IRPulses.normalize(s) {
                return (clean, f)
            }
        }
        return nil
    }

    static func hint(_ dps: [String: JSONValue]) -> IRFormat? {
        if dps["201"] != nil || dps["202"] != nil { return .classic }
        if dps["1"] != nil || dps["13"] != nil { return .modern }
        return nil
    }
}
