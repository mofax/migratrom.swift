/// Topological ordering and validation for the migration DAG.
public func planOrder(
    _ migrations: [Migration],
    appliedIds: Set<Int>
) throws -> [Migration] {
    var byId: [Int: Migration] = [:]
    for migration in migrations {
        if byId[migration.id] != nil {
            throw MigratromError.duplicateMigrationId(migration.id)
        }
        byId[migration.id] = migration
    }

    let roots = migrations.filter { $0.parentId == nil }
    if appliedIds.isEmpty {
        if roots.isEmpty {
            throw MigratromError.missingRoot
        }
        if roots.count > 1 {
            throw MigratromError.multipleRoots(roots.map(\.id))
        }
    } else {
        let newRoots = roots.filter { !appliedIds.contains($0.id) }
        if !newRoots.isEmpty {
            throw MigratromError.multipleRoots(newRoots.map(\.id))
        }
    }

    for migration in migrations {
        guard let parentId = migration.parentId else { continue }
        let parentInBatch = byId[parentId] != nil
        let parentApplied = appliedIds.contains(parentId)
        if !parentInBatch && !parentApplied {
            throw MigratromError.missingParent(migration: migration.id, parent: parentId)
        }
    }

    var depthCache: [Int: Int] = [:]

    func depth(_ id: Int, _ path: inout Set<Int>) throws -> Int {
        if let cached = depthCache[id] {
            return cached
        }

        if path.contains(id) {
            throw MigratromError.cycleDetected(Array(path) + [id])
        }
        path.insert(id)

        guard let migration = byId[id] else {
            depthCache[id] = 0
            path.remove(id)
            return 0
        }

        let d: Int
        if migration.parentId == nil {
            d = 0
        } else {
            d = try depth(migration.parentId!, &path) + 1
        }
        path.remove(id)
        depthCache[id] = d
        return d
    }

    for migration in migrations {
        var path: Set<Int> = []
        _ = try depth(migration.id, &path)
    }

    return migrations
        .filter { !appliedIds.contains($0.id) }
        .sorted { a, b in
            let depthA = depthCache[a.id]!
            let depthB = depthCache[b.id]!
            if depthA != depthB { return depthA < depthB }
            return a.id < b.id
        }
}
