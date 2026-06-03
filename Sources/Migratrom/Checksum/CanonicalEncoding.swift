private let formatVersion = "migratrom/ops/v1"

/// Length-prefixed canonical byte encoding of `[Operation]` (see `docs/CHECKSUM_FORMAT.md`).
public func canonicalEncode(_ ops: [Operation]) -> [UInt8] {
    var bytes: [UInt8] = []
    appendField(formatVersion, to: &bytes)
    appendU32(UInt32(ops.count), to: &bytes)
    for op in ops {
        appendField(op.id, to: &bytes)
        appendField(op.label, to: &bytes)
        bytes.append(op.outsideTransaction ? 1 : 0)
        encodeChecks(op.precheck, to: &bytes)
        encodeSteps(op.execute, to: &bytes)
        encodeChecks(op.postcheck, to: &bytes)
    }
    return bytes
}

private func encodeChecks(_ checks: [Check], to bytes: inout [UInt8]) {
    appendU32(UInt32(checks.count), to: &bytes)
    for check in checks {
        appendField(check.description, to: &bytes)
        appendField(check.sql, to: &bytes)
    }
}

private func encodeSteps(_ steps: [ExecuteStep], to bytes: inout [UInt8]) {
    appendU32(UInt32(steps.count), to: &bytes)
    for step in steps {
        appendField(step.description, to: &bytes)
        appendField(step.sql, to: &bytes)
    }
}

private func appendU32(_ value: UInt32, to bytes: inout [UInt8]) {
    bytes.append(UInt8((value >> 24) & 0xFF))
    bytes.append(UInt8((value >> 16) & 0xFF))
    bytes.append(UInt8((value >> 8) & 0xFF))
    bytes.append(UInt8(value & 0xFF))
}

private func appendField(_ string: String, to bytes: inout [UInt8]) {
    let utf8 = Array(string.utf8)
    appendU32(UInt32(utf8.count), to: &bytes)
    bytes.append(contentsOf: utf8)
}
