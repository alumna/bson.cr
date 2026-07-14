# Changelog

## 0.5.0 - 2026-07-14

### Added
* **binary:** Added `CompressedBSONColumn` (`0x07`) and `Sensitive` (`0x08`) to `BSON::Binary::SubType`.
* **spec:** Synced all standard types with the upstream MongoDB BSON corpus.

### Changed
* **extjson:** `to_relaxed_extjson` for `Datetime` now correctly omits the `.000` fraction for exact-second timestamps.
* **serialization:** Simplified `BSON::Options` camelize annotation extraction.

### Fixed
* **extjson:** `$numberDouble` parser now accepts all valid floating-point strings, not just `NaN` and `Infinity`.
* **extjson:** `$date` parser now explicitly validates the presence of the `$numberLong` key.
* **extjson:** `$code` parser now strictly validates the `$scope` key.
* **core:** `BSON#clear` now correctly writes the initial 5-byte size header.
* **core:** `BSON::ObjectId` counter now correctly uses modulo `0x1000000` for 3-byte overflow wrapping.

### Performance
* **serialization:** `BSON::Serializable` now performs a single-pass O(M) deserialization instead of an O(N×M) multi-pass lookup.
* **core:** BSON key lookups and field skipping now use `LibC.strcmp` and `LibC.strlen`, eliminating heap `String` allocations during document traversal.
* **core:** `BSON::ObjectId` generation now uses direct byte slice manipulation instead of `IO::Memory`, drastically reducing heap allocations.
* **core:** `BSON#[]=` and `BSON#append` now use pre-sized `IO::Memory` buffers to prevent internal reallocations.
* **core:** Serializers now use `write_byte` instead of `write_bytes` with explicit endianness for single-byte primitives.
* **core:** `BSON#to_json` logic blocks were inlined to avoid `Proc` closures.
* **core:** Eliminated redundant `BSON.new` byte array cloning in array builders and `Iterator` generation.

## 0.4.0 - 2026-07-13

### Added
* **binary:** Implemented the BSON Binary Vector specification (Subtype `0x09`) for MongoDB 8.0 compatibility. Includes support for encoding/decoding `FLOAT32` (`0x27`), `INT8` (`0x03`), and `PACKED_BIT` (`0x10`) vector data types.
* **binary:** Added comprehensive validation during Vector encoding and decoding, strictly enforcing bit padding rules, ignored bits masking, and byte multiple constraints.

### Changed
* **tooling:** Bumped the minimum Crystal version constraint in `shard.yml` to `>= 1.20.0`.
* **concurrency:** Migrated the deprecated `Mutex` to `Sync::Mutex` inside `BSON::ObjectId` to conform with Crystal 1.20.0 standards.
* **ci:** Updated `.github/workflows/crystal.yml` to use `ubuntu-24.04` runners and `actions/checkout@v7`, temporarily removing macOS targets.

### Performance
* **binary:** Implemented zero-allocation decoding for `BSON::Binary::Vector`. Extracting numeric arrays (`as_float32`, `as_int8`, `as_packed_bit`) now returns a direct memory view (`Slice(T)`) via `unsafe_slice_of`, avoiding O(N) heap allocations.
* **binary:** Optimized vector encoding methods (`from_vector`, `from_packed_bit_vector`) to write directly into pre-allocated `Bytes` payloads, avoiding intermediate buffers.
