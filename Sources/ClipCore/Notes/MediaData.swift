import Foundation

public struct MediaData: Sendable {
    public let mimeType: String
    public let bytes: Data

    public init?(url: String) {
        guard let delimiter = url.firstIndex(of: ",") else { return nil }
        let header = url[..<delimiter].lowercased()
        guard header.hasPrefix("data:") else { return nil }
        let type = header.dropFirst(5).prefix { $0 != ";" }
        guard type.hasPrefix("image/") || type.hasPrefix("video/") || type.hasPrefix("audio/"),
              let bytes = Self.decode(url[url.index(after: delimiter)...], base64: header.hasSuffix(";base64")),
              !bytes.isEmpty else { return nil }
        mimeType = String(type)
        self.bytes = bytes
    }

    private static func decode(_ payload: Substring, base64: Bool) -> Data? {
        if base64, !payload.contains("%") { return Data(base64Encoded: String(payload)) }
        var result = Data()
        var input = payload.utf8.makeIterator()
        while let byte = input.next() {
            if byte == 37 {
                guard let first = input.next(), let second = input.next(),
                      let high = hex(first), let low = hex(second) else { return nil }
                result.append(high * 16 + low)
            } else {
                result.append(byte)
            }
        }
        return base64 ? Data(base64Encoded: result) : result
    }

    private static func hex(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }
}
