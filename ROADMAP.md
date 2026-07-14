# ROADMAP

## Project Context

This project is an active fork (`alumna/bson.cr`) originally based on `elbywan/bson.cr`. It provides a pure Crystal implementation of the BSON specification.
- **Goal:** modernization for Crystal 1.20+, and acting as a foundation for the `cryomongo` updated driver targeting MongoDB 8.0.
- **Target OS:** Linux exclusively (Debian 13 / Ubuntu 24.04). The other OSed later, when the update is concluded.
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

---

## Future Stage: Integration & Upstream
With the BSON foundation now fully optimized and compliant with MongoDB 8.0 specs, the focus shifts to utilizing this fork within the `alumna/cryomongo` driver. Once `cryomongo` is stabilized and tested in production, a comprehensive PR will be compiled to propose merging these enhancements back into the original `elbywan/bson.cr` upstream repository.
