import Foundation

public protocol MigrationLogger: Sendable {
    func info(_ message: String, metadata: String?)
    func warn(_ message: String, metadata: String?)
    func error(_ message: String, metadata: String?)
}

extension MigrationLogger {
    public func info(_ message: String) { info(message, metadata: nil) }
    public func warn(_ message: String) { warn(message, metadata: nil) }
    public func error(_ message: String) { error(message, metadata: nil) }
}

public struct ConsoleLogger: MigrationLogger, Sendable {
    public init() {}

    public func info(_ message: String, metadata: String?) {
        print(message, metadata.map { " \($0)" } ?? "", separator: "")
    }

    public func warn(_ message: String, metadata: String?) {
        let line = "warning: \(message)\(metadata.map { " \($0)" } ?? "")\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    public func error(_ message: String, metadata: String?) {
        let line = "error: \(message)\(metadata.map { " \($0)" } ?? "")\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
