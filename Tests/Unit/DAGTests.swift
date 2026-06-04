import Testing
@testable import Migratrom

private func migration(_ id: Int, _ parentId: Int? = nil) -> Migration {
    Migration(id: id, parentId: parentId, operations: [])
}

@Suite struct DAGTests {
    @Test func ordersParentBeforeChild() throws {
        let result = try planOrder([migration(2, 1), migration(1)], appliedIds: [])
        #expect(result.map(\.id) == [1, 2])
    }

    @Test func tiebreaksSiblingsByIdAsc() throws {
        let result = try planOrder([migration(3, 1), migration(2, 1), migration(1)], appliedIds: [])
        #expect(result.map(\.id) == [1, 2, 3])
    }

    @Test func filtersAlreadyApplied() throws {
        let result = try planOrder([migration(1), migration(2, 1)], appliedIds: [1])
        #expect(result.map(\.id) == [2])
    }

    @Test func allowsParentOnlyInAppliedIds() throws {
        let result = try planOrder([migration(2, 1)], appliedIds: [1])
        #expect(result.map(\.id) == [2])
    }

    @Test func duplicateId() {
        #expect(throws: MigratromError.self) {
            try planOrder([migration(1), migration(1)], appliedIds: [])
        }
    }

    @Test func missingRootOnEmptyHistory() {
        #expect(throws: MigratromError.self) {
            try planOrder([migration(2, 1)], appliedIds: [])
        }
    }

    @Test func multipleRootsOnEmptyHistory() {
        #expect(throws: MigratromError.self) {
            try planOrder([migration(1), migration(2)], appliedIds: [])
        }
    }

    @Test func newRootWhenHistoryNonEmpty() {
        #expect(throws: MigratromError.self) {
            try planOrder([migration(2)], appliedIds: [1])
        }
    }

    @Test func reListedAppliedRootIsHarmless() throws {
        let result = try planOrder([migration(1), migration(2, 1)], appliedIds: [1])
        #expect(result.map(\.id) == [2])
    }

    @Test func missingParent() {
        #expect(throws: MigratromError.self) {
            try planOrder([migration(1), migration(2, 99)], appliedIds: [])
        }
    }

    @Test func cycleDetection() {
        let a = Migration(id: 1, parentId: 2, operations: [])
        let b = Migration(id: 2, parentId: 1, operations: [])
        #expect(throws: MigratromError.self) {
            try planOrder([a, b], appliedIds: [100])
        }
    }
}
