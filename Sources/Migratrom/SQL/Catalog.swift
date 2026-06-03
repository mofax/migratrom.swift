private func existsSelect(_ exists: String, negate: Bool) -> String {
    negate ? "SELECT NOT \(exists)" : "SELECT \(exists)"
}

public func columnExistsSql(
    _ schema: String,
    _ table: String,
    _ column: String,
    negate: Bool
) -> String {
    let exists = """
    EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = \(quoteLiteral(schema))
          AND table_name = \(quoteLiteral(table))
          AND column_name = \(quoteLiteral(column))
      )
    """
    return existsSelect(exists, negate: negate)
}

public func constraintExistsSql(
    _ schema: String,
    _ table: String,
    _ constraintName: String,
    negate: Bool
) throws -> String {
    let reg = try regclassLiteral(schema, table)
    let name = quoteLiteral(constraintName)
    let exists =
        "EXISTS (SELECT 1 FROM pg_constraint WHERE conname = \(name) AND conrelid = \(reg)::regclass)"
    return existsSelect(exists, negate: negate)
}

public func primaryKeyExistsSql(_ schema: String, _ table: String, negate: Bool) throws -> String {
    let reg = try regclassLiteral(schema, table)
    let exists =
        "EXISTS (SELECT 1 FROM pg_constraint WHERE contype = 'p' AND conrelid = \(reg)::regclass)"
    return existsSelect(exists, negate: negate)
}

public func checkConstraintExistsSql(
    _ schema: String,
    _ table: String,
    _ constraintName: String,
    negate: Bool
) throws -> String {
    let reg = try regclassLiteral(schema, table)
    let name = quoteLiteral(constraintName)
    let exists =
        "EXISTS (SELECT 1 FROM pg_constraint WHERE conname = \(name) AND contype = 'c' AND conrelid = \(reg)::regclass)"
    return existsSelect(exists, negate: negate)
}

public func schemaExistsSql(_ schema: String, negate: Bool) -> String {
    let exists = """
    EXISTS (
        SELECT 1 FROM information_schema.schemata
        WHERE schema_name = \(quoteLiteral(schema))
      )
    """
    return existsSelect(exists, negate: negate)
}

public func extensionExistsSql(_ name: String, negate: Bool) -> String {
    let exists = "EXISTS (SELECT 1 FROM pg_extension WHERE extname = \(quoteLiteral(name)))"
    return existsSelect(exists, negate: negate)
}

public func regclassExistsSql(_ schema: String, _ name: String, negate: Bool) throws -> String {
    let reg = try regclassLiteral(schema, name)
    return negate ? "SELECT to_regclass(\(reg)) IS NULL" : "SELECT to_regclass(\(reg)) IS NOT NULL"
}

public func enumTypeExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
    let exists = """
    EXISTS (
        SELECT 1 FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = \(quoteLiteral(schema))
          AND t.typname = \(quoteLiteral(name))
          AND t.typtype = 'e'
      )
    """
    return existsSelect(exists, negate: negate)
}

public func enumLabelExistsSql(
    _ schema: String,
    _ typeName: String,
    _ value: String,
    negate: Bool
) -> String {
    let exists = """
    EXISTS (
        SELECT 1 FROM pg_enum e
        JOIN pg_type t ON t.oid = e.enumtypid
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = \(quoteLiteral(schema))
          AND t.typname = \(quoteLiteral(typeName))
          AND e.enumlabel = \(quoteLiteral(value))
      )
    """
    return existsSelect(exists, negate: negate)
}

public func viewExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
    let exists = """
    EXISTS (
        SELECT 1 FROM information_schema.views
        WHERE table_schema = \(quoteLiteral(schema))
          AND table_name = \(quoteLiteral(name))
      )
    """
    return existsSelect(exists, negate: negate)
}

public func matviewExistsSql(_ schema: String, _ name: String, negate: Bool) -> String {
    let exists =
        "EXISTS (SELECT 1 FROM pg_matviews WHERE matviewname = \(quoteLiteral(name)) AND schemaname = \(quoteLiteral(schema)))"
    return existsSelect(exists, negate: negate)
}

public func columnDefaultSetSql(
    _ schema: String,
    _ table: String,
    _ column: String,
    negate: Bool
) -> String {
    let exists = """
    EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = \(quoteLiteral(schema))
          AND table_name = \(quoteLiteral(table))
          AND column_name = \(quoteLiteral(column))
          AND column_default IS NOT NULL
      )
    """
    return existsSelect(exists, negate: negate)
}

public func columnNotNullSql(
    _ schema: String,
    _ table: String,
    _ column: String,
    negate: Bool
) -> String {
    let exists = """
    EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = \(quoteLiteral(schema))
          AND table_name = \(quoteLiteral(table))
          AND column_name = \(quoteLiteral(column))
          AND is_nullable = 'NO'
      )
    """
    return existsSelect(exists, negate: negate)
}

/// Qualified relation for `ALTER TABLE` targets.
public func alterTable(_ schema: String, _ table: String) throws -> String {
    try qualified(schema, table)
}
