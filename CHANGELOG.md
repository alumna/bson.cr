# Changelog

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
