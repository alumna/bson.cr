# ROADMAP

## Project Context

This project is an active fork (`alumna/bson.cr`) originally based on `elbywan/bson.cr`. It provides a pure Crystal implementation of the BSON specification.
- **Goal:** modernization for Crystal 1.20+, and acting as a foundation for the `cryomongo` updated driver targeting MongoDB 8.0.
- **Target OS:** Linux exclusively (Debian 13 / Ubuntu 24.04). The other OS later, when the update is concluded.
- **Target Compiler:** Crystal 1.20+. Strict avoidance of deprecated standard library modules.

---

## Phases & Progress

### Phase 1: Tooling, Crystal 1.20, and Binary Vector Support [Completed]
- [x] Create `ROADMAP.md` to define boundaries and upcoming steps.
- [x] **Crystal 1.20 Modernization:** Update `shard.yml` dependencies, bump GitHub actions to `ubuntu-24.04`, and fix `Mutex` deprecations (now `Sync::Mutex`).
- [x] **BSON Binary Vector (`0x09`):** Scaffold `0x09` subtype in the enum and implement specific padding/decoding logic passing `float32`, `int8`, and `packed_bit` validation tests.

### Phase 2: BSON Corpus Sync (Part A - Standard Types) [Completed]
- [x] Replace existing JSONs. Run the spec suite, fix breakages. Address edge cases in parsing.
- [x] Synced: `array`, `binary`, `boolean`, `datetime`, `document`, `string`, `double`, `int32`, `int64`, `null`, `maxkey`, `minkey`, `symbol`, `undefined`.

### Phase 3: BSON Corpus Sync (Part B - Complex Types) [Completed]
- [x] Resolve `ignore_json_roundtrip` hacks added by the original author.
- [x] Implement the `parseErrors` suite to guarantee strict Extended JSON boundaries.
- [x] Synced: `decimal128-*.json`, `code`, `code_w_scope`, `dbref`, `regex`, `timestamp`, `oid`, `top`, `multi-type`, `multi-type-deprecated`, `dbpointer`.

### Phase 4: BSON Binary Encrypted, Decimal128 Rewrite & Zero-Allocation ExtJSON [Completed]
- [x] **Decimal128:** Dropped `LibGMP` (`BigInt`) dependency. Rewrote `Decimal128` to use native `UInt128` bitwise operations, reducing struct size to exactly 16 bytes.
- [x] **Zero-Allocation:** Replaced intermediate string allocations during Extended JSON generation with direct IO streaming (`builder.string { |io| ... }`).
- [x] **Encrypted BSON:** Ensured `to_json` and `to_canonical_extjson` outputs perfectly align with the MongoDB specs for subtype `0x06` via optimized base64 slice streaming.

### Phase 5: Complete review: Correctness, performance, views, and test corpus folder layout [Completed]
- [x] Native BSON round-trip in the corpus runner (`canonicalize`, `degenerate_bson`, `degenerate_extjson`).
- [x] Crystal 1.21 regex flags (`m` / `s`), alphabetical option letters, and null-byte checks on encode.
- [x] Inline `ObjectId` bytes, unsigned timestamp accessors, and `Atomic` counter.
- [x] Nested document views, one-pass `to_bson` for `Serializable`, and UUID representation helpers.
- [x] Corpus files now follow the official MongoDB folder layout.

### Phase 6: Finish remaining spec types and Cryomongo helpers [Completed]
- [x] `BSON::Regex` stores pattern and options as text. No PCRE compile on decode.
- [x] `BSON::DateTime` stores `int64` milliseconds. Y10K and other values outside Crystal `Time` are kept.
- [x] `BigDecimal` support is optional: `require "bson/optional/big_decimal"`. The default path does not load LibGMP.
- [x] ObjectId process-unique bytes are rebuilt after `fork` on Unix (`pthread_atfork`).
- [x] `BSON.parse` / `parse?`, `from_json?`, `from_io?`, `BSON.build`, and public `BSON::Builder` for Cryomongo.

---

## Future Stage: Integration & Upstream

The BSON shard is complete for MongoDB 8.0. Next work is the `alumna/cryomongo` driver. When that driver is stable in production, we will open a PR to merge this fork back into `elbywan/bson.cr`.
