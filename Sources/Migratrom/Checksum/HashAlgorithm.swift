import Crypto

public struct HashAlgorithm: Sendable {
    public let name: String
    public let hash: @Sendable ([UInt8]) -> [UInt8]

    public init(name: String, hash: @escaping @Sendable ([UInt8]) -> [UInt8]) {
        self.name = name
        self.hash = hash
    }

    public static let sha256 = HashAlgorithm(name: "sha256") { bytes in
        Array(SHA256.hash(data: bytes))
    }

    private static let registry: [String: HashAlgorithm] = [
        "sha256": .sha256,
    ]

    public static func named(_ name: String) -> HashAlgorithm? {
        registry[name]
    }

    public static let `default` = sha256
}
