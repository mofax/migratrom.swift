# migratrom checksum format

Normative specification for the self-describing migration checksum used by
[migratrom.swift](https://github.com/mofax/migratrom.swift). Other language ports
(including the TypeScript reference implementation) must reproduce this format
byte-for-byte to interoperate on the same history table.

## Stored checksum string

Applied migrations store a single text checksum:

```
<algorithm-name>/<lowercase-hex-digest>
```

Example:

```
sha256/94ed9b803f3f1aab13781edaf6ffbba94834295dce1ca5a64ac5135bd5998505
```

- **Algorithm prefix** — ASCII name before the first `/`. Identifies which hash
  function produced the digest. Parsers split on the **first** `/` only (digest
  hex never contains `/`).
- **Hex digest** — lowercase hexadecimal encoding of the raw hash output (64
  hex chars for SHA-256). Comparisons are case-insensitive.
- **Unknown algorithm** — verification must fail if the prefix is not registered
  (do not guess).

The default algorithm is **SHA-256** (`sha256`). New algorithms can be added later
without changing the canonical encoding; only the prefix and digest length change.

## What gets hashed

The digest is computed over the **canonical byte encoding** of a migration’s
`operations` array (not over JSON, CBOR, or SQL text). The encoding is defined
below.

```
checksum(operations) = algorithm_name + "/" + hex_lower( hash( canonical(operations) ) )
```

## Logical model (field order)

Each migration has an ordered list of **operations**. Each operation contains:

| Field | Type | Notes |
|-------|------|--------|
| `id` | string | Stable logical id, e.g. `table.user` |
| `label` | string | Human label, e.g. `Create table "user"` |
| `outsideTransaction` | boolean | Encoded as `u8`: `0` or `1` |
| `precheck` | array of **Check** | Order preserved |
| `execute` | array of **ExecuteStep** | Order preserved |
| `postcheck` | array of **Check** | Order preserved |

**Check** and **ExecuteStep** each have:

| Field | Type |
|-------|------|
| `description` | string |
| `sql` | string |

All strings are UTF-8. There is no key sorting, escaping, or normalization beyond
using UTF-8 bytes as authored. Cross-language interop additionally requires
operation builders to emit **identical** `id`, `label`, `description`, and `sql`
strings (the Swift and TS ports must share the same builder output).

## Binary encoding

### Primitives

| Name | Layout |
|------|--------|
| `u8(n)` | One byte, value `n` (0–255) |
| `u32(n)` | Four bytes, **big-endian** unsigned 32-bit integer |
| `field(s)` | `u32(byte_length_utf8(s))` then the UTF-8 bytes of `s` |

`field` length is the number of **UTF-8 bytes**, not Unicode scalars or code units
in UTF-16 environments.

### Top-level: `canonical(operations)`

```
field("migratrom/ops/v1")     # format version tag (future versions use a new tag)
u32(operations.length)
for each operation in array order (index 0 .. n-1):
  field(operation.id)
  field(operation.label)
  u8(operation.outsideTransaction ? 1 : 0)
  encode_checks(operation.precheck)
  encode_steps(operation.execute)
  encode_checks(operation.postcheck)
```

### `encode_checks(checks)`

```
u32(checks.length)
for each check in array order:
  field(check.description)
  field(check.sql)
```

### `encode_steps(steps)`

```
u32(steps.length)
for each step in array order:
  field(step.description)
  field(step.sql)
```

Field order is **positional** everywhere; lengths disambiguate boundaries.

## SHA-256

- Input: canonical byte sequence.
- Output: 32-byte digest.
- Hex: 64 lowercase hex characters (no `0x`, no separators).

## Worked example (golden vector)

The following single-operation migration is the reference vector used by unit
tests (`GoldenSample` in todo 14). Reimplementations must match **exactly**.

### Operation (JSON for readability only — not part of the format)

```json
{
  "id": "table.user",
  "label": "Create table \"user\"",
  "outsideTransaction": false,
  "precheck": [
    {
      "description": "ensure table \"public\".\"user\" does not exist",
      "sql": "SELECT NOT EXISTS (\n  SELECT 1 FROM pg_class c\n  JOIN pg_namespace n ON n.oid = c.relnamespace\n  WHERE n.nspname = 'public' AND c.relname = 'user'\n)"
    }
  ],
  "execute": [
    {
      "description": "create table \"user\"",
      "sql": "CREATE TABLE \"public\".\"user\" (\n  \"id\" bigint PRIMARY KEY\n)"
    }
  ],
  "postcheck": [
    {
      "description": "ensure table \"public\".\"user\" exists",
      "sql": "SELECT EXISTS (\n  SELECT 1 FROM pg_class c\n  JOIN pg_namespace n ON n.oid = c.relnamespace\n  WHERE n.nspname = 'public' AND c.relname = 'user'\n)"
    }
  ]
}
```

(SQL strings use a single newline after `(` and before `)` as shown; no trailing
newline after the closing `)`.)

### Canonical bytes (hex)

```
00000010 6d6967726174726f6d2f6f70732f7631   # field "migratrom/ops/v1"
00000001                             # u32: 1 operation
0000000a 7461626c652e75736572            # field "table.user"
00000013 437265617465207461626c6520227573657222  # field label
00                                   # u8: outsideTransaction = false
00000001                             # 1 precheck
0000002b 656e73757265207461626c6520227075626c6963222e22757365722220646f6573206e6f74206578697374
00000094 53454c454354204e4f54204558495354532028 ...  # precheck sql (148 utf8 bytes)
00000001                             # 1 execute step
00000013 637265617465207461626c6520227573657222
0000003a 435245415445205441424c4520227075626c6963222e2275736572222028 ...
00000001                             # 1 postcheck
00000023 656e73757265207461626c6520227075626c6963222e22757365722220657869737473
00000090 53454c454354204558495354532028 ...
```

**Full canonical hex (single line, no spaces):**

```
000000106d6967726174726f6d2f6f70732f7631000000010000000a7461626c652e7573657200000013437265617465207461626c652022757365722200000000010000002b656e73757265207461626c6520227075626c6963222e22757365722220646f6573206e6f742065786973740000009453454c454354204e4f542045584953545320280a202053454c45435420312046524f4d2070675f636c61737320630a20204a4f494e2070675f6e616d657370616365206e204f4e206e2e6f6964203d20632e72656c6e616d6573706163650a20205748455245206e2e6e73706e616d65203d20277075626c69632720414e4420632e72656c6e616d65203d202775736572270a290000000100000013637265617465207461626c65202275736572220000003a435245415445205441424c4520227075626c6963222e22757365722220280a20202269642220626967696e74205052494d415259204b45590a290000000100000023656e73757265207461626c6520227075626c6963222e227573657222206578697374730000009053454c4543542045584953545320280a202053454c45435420312046524f4d2070675f636c61737320630a20204a4f494e2070675f6e616d657370616365206e204f4e206e2e6f6964203d20632e72656c6e616d6573706163650a20205748455245206e2e6e73706e616d65203d20277075626c69632720414e4420632e72656c6e616d65203d202775736572270a29
```

### Checksum

```
sha256/94ed9b803f3f1aab13781edaf6ffbba94834295dce1ca5a64ac5135bd5998505
```

## Verification algorithm

1. Parse stored value into `(algo, hex)` via first `/`.
2. Resolve `algo` in the algorithm registry; fail if unknown.
3. `canonical = canonical_encode(current_operations)`.
4. `actual_hex = hex_lower(hash_algo(canonical))`.
5. Compare `hex` to `actual_hex` case-insensitively; on mismatch, report
   checksum drift (migration body was edited after apply).

## Porting checklist (TypeScript and others)

1. Implement `field`, `u32`, `u8`, `encode_checks`, `encode_steps`, and
   `canonical(operations)` exactly as above.
2. Register `sha256` as SHA-256 over the canonical bytes; emit lowercase hex.
3. Ensure every operation builder emits the **same** `id`, `label`,
   `description`, and `sql` strings as the Swift package (byte-identical UTF-8).
4. Assert the golden vector in this document in your test suite.
5. Store checksums as `"<algo>/<hex>"` in the history table; verify on re-apply
   before running pending migrations.
