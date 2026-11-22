import Foundation

/// A number of bytes that formats with decimal units, the way Finder does.
public struct ByteCount: Hashable, Comparable, Sendable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    public var bytes: UInt64

    public init(_ bytes: UInt64) {
        self.bytes = bytes
    }

    public init(integerLiteral value: UInt64) {
        self.bytes = value
    }

    public static let zero = ByteCount(0)

    public static func < (lhs: ByteCount, rhs: ByteCount) -> Bool {
        lhs.bytes < rhs.bytes
    }

    /// Adds two counts, saturating at `UInt64.max` instead of trapping.
    public static func + (lhs: ByteCount, rhs: ByteCount) -> ByteCount {
        let (sum, overflow) = lhs.bytes.addingReportingOverflow(rhs.bytes)
        return ByteCount(overflow ? .max : sum)
    }

    public static func += (lhs: inout ByteCount, rhs: ByteCount) {
        lhs = lhs + rhs
    }

    /// "1.2 GB" in the user's locale, exactly as Finder shows it ("999 bytes", "1 KB").
    public var formatted: String {
        Self.formatter.string(fromByteCount: Int64(clamping: bytes))
    }

    // The classic formatter matches Finder; the newer FormatStyle prints "kB" and rounds
    // small sizes up. Formatters are thread-safe once configured.
    nonisolated(unsafe) private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    public var description: String { formatted }
}

extension ByteCount: Codable {
    public init(from decoder: any Decoder) throws {
        bytes = try decoder.singleValueContainer().decode(UInt64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(bytes)
    }
}
