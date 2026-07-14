# ROADMAP.md

## Project Context
This project is an active, organization-owned fork (`alumna/bson.cr`) originally based on `elbywan/bson.cr`. It provides a pure Crystal implementation of the BSON specification.
- **Goal:** Supply-chain security, modernization for Crystal 1.20+, and acting as a robust foundation for the `cryomongo` enterprise driver targeting MongoDB 8.0.
- **Target OS:** Linux exclusively (Debian 13 / Ubuntu 24.04).
- **Target Compiler:** Crystal 1.20+. Strict avoidance of deprecated standard library modules.

## Architecture & Technical Debt Guidelines
1. **Spec Compliance is Absolute:** Must maintain 100% compatibility with official `mongodb/specifications` corpus tests.
2. **Performance Constraints:** This runs on *every* database I/O boundary. Minimize memory allocations.
3. **Decimal128:** Currently parsed via strings (slow). Short-term: stabilize and pass corpus. Long-term: native bitwise implementation or `libmpdec`.
4. **Extended JSON (extJSON):** Exact representation matching is critical, as MongoDB drivers rely on this for logging, debugging, and mock testing.

---

## Phases & Progress

### Phase 1: Tooling, Crystal 1.20, and Binary Vector Support [Done]
- [x] Create `ROADMAP.md` to define boundaries and upcoming steps.
- [x] **Crystal 1.20 Modernization:** Update `shard.yml` dependencies, bump GitHub actions to `ubuntu-24.04`, and fix `Mutex` deprecations (now `Sync::Mutex`).
- [x] **BSON Binary Vector (`0x09`):** Scaffold `0x09` subtype in the enum and implement specific padding/decoding logic passing `float32`, `int8`, and `packed_bit` validation tests.

### Phase 2: BSON Corpus Sync (Part A - Standard Types) [Done]
- [x] **Target:** Update the out-of-date corpus test files in `spec/corpus/`.
- [x] **Files to Sync:** `array`, `binary`, `boolean`, `datetime`, `document`, `string`, `double`, `int32`, `int64`, `null`, `maxkey`, `minkey`, `symbol`, `undefined`
- [x] **Goal:** Replace existing JSONs. Run the spec suite, fix breakages. Address edge cases in parsing.

### Phase 3: BSON Corpus Sync (Part B - Complex Types) [Done]
- [x] **Target:** Update remaining complex corpus tests.
- [x] **Files to Sync:** `decimal128-*.json`, `code`, `code_w_scope`, `dbref`, `regex`, `timestamp`, `oid`, `top`, `multi-type`, `multi-type-deprecated`, `dbpointer`
- [x] **Goal:** Resolve `ignore_json_roundtrip` hacks added by the original author. Ensure `Decimal128` string parsing can handle the modern spec cases.

### Phase 4: BSON Binary Encrypted & Extended JSON Audit [Pending]
- **Target:** Implement `bson-binary-encrypted/binary-encrypted.md`.
- **Goal:** Ensure `to_json` (Relaxed) and `to_canonical_extjson` (Canonical) outputs perfectly align with the MongoDB specs for subtype `0x06`. We don't need cryptography implementations here, just accurate binary enveloping and extJSON conversion.
