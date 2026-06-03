import Testing
@testable import Migratrom

enum GoldenSample {
    static let operation = Operation(
        id: "table.user",
        label: "Create table \"user\"",
        precheck: [
            Check(
                description: "ensure table \"public\".\"user\" does not exist",
                sql: """
                SELECT NOT EXISTS (
                  SELECT 1 FROM pg_class c
                  JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'user'
                )
                """.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
        ],
        execute: [
            ExecuteStep(
                description: "create table \"user\"",
                sql: """
                CREATE TABLE "public"."user" (
                  "id" bigint PRIMARY KEY
                )
                """.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
        ],
        postcheck: [
            Check(
                description: "ensure table \"public\".\"user\" exists",
                sql: """
                SELECT EXISTS (
                  SELECT 1 FROM pg_class c
                  JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'public' AND c.relname = 'user'
                )
                """.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
        ]
    )

    static let canonicalHex =
        "000000106d6967726174726f6d2f6f70732f7631000000010000000a7461626c652e7573657200000013437265617465207461626c652022757365722200000000010000002b656e73757265207461626c6520227075626c6963222e22757365722220646f6573206e6f742065786973740000009453454c454354204e4f542045584953545320280a202053454c45435420312046524f4d2070675f636c61737320630a20204a4f494e2070675f6e616d657370616365206e204f4e206e2e6f6964203d20632e72656c6e616d6573706163650a20205748455245206e2e6e73706e616d65203d20277075626c69632720414e4420632e72656c6e616d65203d202775736572270a290000000100000013637265617465207461626c65202275736572220000003a435245415445205441424c4520227075626c6963222e22757365722220280a20202269642220626967696e74205052494d415259204b45590a290000000100000023656e73757265207461626c6520227075626c6963222e227573657222206578697374730000009053454c4543542045584953545320280a202053454c45435420312046524f4d2070675f636c61737320630a20204a4f494e2070675f6e616d657370616365206e204f4e206e2e6f6964203d20632e72656c6e616d6573706163650a20205748455245206e2e6e73706e616d65203d20277075626c69632720414e4420632e72656c6e616d65203d202775736572270a29"

    static let checksum =
        "sha256/94ed9b803f3f1aab13781edaf6ffbba94834295dce1ca5a64ac5135bd5998505"
}

@Suite struct ChecksumTests {
    @Test func goldenCanonicalEncoding() {
        let hex = hexLower(canonicalEncode([GoldenSample.operation]))
        #expect(hex == GoldenSample.canonicalHex)
    }

    @Test func goldenChecksumString() {
        #expect(checksum([GoldenSample.operation]) == GoldenSample.checksum)
    }

    @Test func parseAndVerifyRoundTrip() throws {
        let digest = checksum([GoldenSample.operation])
        let parsed = try parseChecksum(digest)
        #expect(parsed.algo == "sha256")
        #expect(parsed.hex == GoldenSample.checksum.split(separator: "/").last.map(String.init))
        try verifyChecksum(digest, against: [GoldenSample.operation], migrationId: 1)
    }

    @Test func unknownAlgorithmFailsVerification() {
        #expect(throws: MigratromError.self) {
            try verifyChecksum("unknown/deadbeef", against: [GoldenSample.operation], migrationId: 1)
        }
    }

    @Test func checksumMismatchOnEditedOps() {
        var edited = GoldenSample.operation
        edited.execute[0].sql += " "
        #expect(throws: MigratromError.self) {
            try verifyChecksum(GoldenSample.checksum, against: [edited], migrationId: 1)
        }
    }
}
