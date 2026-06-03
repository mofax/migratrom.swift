/// Double-quote an identifier, escaping embedded double-quotes by doubling.
public func quoteIdent(_ name: String) throws -> String {
    if name.contains("\0") {
        throw MigratromError.config("identifier contains NUL")
    }
    return "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
}

/// Single-quote a string literal, escaping embedded single-quotes by doubling.
public func quoteLiteral(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "''"))'"
}

/// Fully-qualified relation name: `"schema"."table"`.
public func qualified(_ schema: String, _ name: String) throws -> String {
    try "\(quoteIdent(schema)).\(quoteIdent(name))"
}

/// A string literal usable inside `to_regclass(...)`: `'"schema"."table"'`.
public func regclassLiteral(_ schema: String, _ name: String) throws -> String {
    try quoteLiteral(qualified(schema, name))
}

/// Comma-joined quoted column list: `"a", "b"`.
public func quoteIdentList(_ names: [String]) throws -> String {
    try names.map(quoteIdent).joined(separator: ", ")
}
