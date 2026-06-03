/// Self-describing checksum: `"<algo>/<lowercase-hex>"`.
public func checksum(
    _ ops: [Operation],
    algorithm: HashAlgorithm = .default
) -> String {
    let digest = algorithm.hash(canonicalEncode(ops))
    return "\(algorithm.name)/\(hexLower(digest))"
}

public func parseChecksum(_ stored: String) throws -> (algo: String, hex: String) {
    guard let slash = stored.firstIndex(of: "/") else {
        throw MigratromError.config("malformed checksum (missing '/'): \(stored)")
    }
    let algo = String(stored[..<slash])
    let hex = String(stored[stored.index(after: slash)...])
    guard !algo.isEmpty, !hex.isEmpty else {
        throw MigratromError.config("malformed checksum: \(stored)")
    }
    return (algo, hex)
}

/// Recomputes the checksum for `ops` and compares it to `stored`.
public func verifyChecksum(
    _ stored: String,
    against ops: [Operation],
    migrationId: Int
) throws {
    let parsed = try parseChecksum(stored)
    guard let algorithm = HashAlgorithm.named(parsed.algo) else {
        throw MigratromError.config("unknown checksum algorithm: \(parsed.algo)")
    }
    let actual = checksum(ops, algorithm: algorithm)
    let actualParsed = try parseChecksum(actual)
    guard parsed.hex.caseInsensitiveCompare(actualParsed.hex) == .orderedSame else {
        throw MigratromError.checksumMismatch(
            id: migrationId,
            stored: stored,
            actual: actual
        )
    }
}

public func hexLower(_ bytes: [UInt8]) -> String {
    let digits = Array("0123456789abcdef".utf8)
    var hex = String()
    hex.reserveCapacity(bytes.count * 2)
    for byte in bytes {
        hex.append(Character(UnicodeScalar(digits[Int(byte >> 4)])))
        hex.append(Character(UnicodeScalar(digits[Int(byte & 0x0F)])))
    }
    return hex
}
