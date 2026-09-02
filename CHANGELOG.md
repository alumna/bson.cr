# Changelog

## 0.9.2 - 2026-09-02

### Performance
* **decoder / `to_h`:** Intern `"left"`, `"right"`, `"leftValue"`, `"rightValue"` by size and `memcmp`. Other keys stay `String.new`. No intern table. Keys are C-strings (no UTF-8 check). String values still check UTF-8.
* Deep decode 119 → **134** MB/s (repeat 130). BSONBench 1103 → 1069 (encode / flat / full in the noise). Public `to_h` types are unchanged.

## 0.9.1 - 2026-09-02

### Changed
* **core:** `BSON.new(Array)` uses `Builder::STATIC_INDICES` for keys `0..127` (same as nested array encode).

### Performance
* **decoder / `to_h`:** Nested documents and arrays fill `Hash` / `Array` in one pass (no child `BSON.view`, no `Enumerable#map`). Empty collections use capacity 0. Do not pre-size documents from `(size-5)//4` (nested child bytes inflate the hint). Public `to_h` types are unchanged.
* Improvements: flat decode 905 → **1179** MB/s; deep decode 100 → **119** MB/s; full decode 772 → **828** MB/s; BSONBench 1018 → **1103**.

## 0.9.0 - 2026-09-01

### Added
* **builder:** `Builder#document(key, &)` and `Builder#array(key, &)` write a nested document or array into the same IO (size placeholder, then patch). `[]=(Hash)` and `[]=(Array)` use them, so nested Hash/Array encode no longer allocates a child BSON.

## 0.8.1 - 2026-08-18

### Fixed
* **serializable:** better handling of types:
  `BSON::Value` has both `Time` and `DateTime`, and both regex types.
  `from_bson` for `Serializable`, `Array`, and `Hash` now writes one `when` pair for each.
  Fields of type `BSON::Value` or `Array(BSON::Value)` compile again.

## 0.8.0 - 2026-08-18

### Added
* **datetime:** Added `BSON::DateTime` (`int64` milliseconds). Values outside Crystal `Time` (for example Y10K) are kept. Use `#to_time` / `#to_time?`.
* **regex:** Added `BSON::Regex` with `pattern` and `options` as text. Decode does not compile PCRE. Use `#to_regex` / `#to_regex?` when you need a Crystal `Regex`.
* **error:** Added `BSON::Error` for bad BSON bytes and bad Extended JSON.
* **core:** Added `BSON.view` for a document that reads an existing buffer without a copy.
* **core:** Added `BSON#canonicalize` to encode decoded values again. Degenerate array keys and regex options become canonical.
* **core:** Added `BSON.build`, public `BSON::Builder`, and `BSON#append` with a block so many fields can be written with one buffer rebuild.
* **core:** Added `BSON.parse` / `parse?`, `from_json?`, and `from_io?`.
* **object_id:** Added `timestamp` (`UInt32`) and `generation_time` (`Time`). The timestamp is unsigned, as required by the spec.
* **object_id:** After `fork` on Unix, process-unique bytes and the counter are rebuilt.
* **binary:** Added `UuidRepresentation` and `as_uuid` helpers for standard, C#, Java, and Python UUID byte orders.
* **decimal128:** Added optional `require "bson/optional/big_decimal"` for `BigDecimal` convert.
* **spec:** Added prose tests for null bytes, ObjectId timestamps, UUID representations, packed-bit ignored bits, DateTime Y10K, `BSON::Regex`, and `parse?`.

### Changed
* Decode of BSON datetime now returns `BSON::DateTime` instead of `Time`.
* Decode of BSON regex now returns `BSON::Regex` instead of Crystal `Regex`.
* `BSON::Serializable`, `Hash`, `Array`, and `NamedTuple` still accept `Time` and Crystal `Regex` fields.
* The default Decimal128 path no longer does `require "big"`.
* Missing keys raise `KeyError`.
* Regex `m` maps to `MULTILINE_ONLY` and `s` maps to `DOTALL` (Crystal 1.21). Option letters are written in alphabetical order: `i`, `m`, `s`, `u`, `x`.
* **object_id:** Store the 12 bytes in a `StaticArray`. Generation uses `Atomic(UInt32)` instead of `Sync::Mutex`.
* **serializable:** `to_bson` writes all fields in one builder pass.
* **corpus:** Moved corpus JSON files to `spec/corpus/bson-corpus/tests/` and `spec/corpus/bson-binary-vector/tests/` to match the official MongoDB layout. The runner now checks native round-trip, `degenerate_bson`, and `degenerate_extjson`. The official Y10K datetime case runs.

### Performance
* **builder / Cryomongo:** `BSON.build` and public `Builder` avoid repeated `[]=` rebuilds when you write a command or a reply.
* **decoder:** Nested documents and arrays use `BSON.view` and do not clone the parent buffer.
* **regex:** Decode no longer compiles PCRE. Queries that only store or send the pattern stay cheap.
* **datetime:** DateTime is one `Int64`. No `Time` allocation on decode.
* **object_id:** Hex parse writes into the inline 12-byte array. No heap ObjectId buffer. Generation uses `Atomic`, not a mutex.
* **fetch:** A key hit no longer allocates a second `String` for the same key.
* **extjson:** `Float64` canonical output writes through a stack buffer and maps `e` to `E`.
* **decimal128:** Significand digits are read into `UInt128` without a second string-to-number pass. LibGMP is not linked unless you require the BigDecimal helper.
* **parse? / from_json?:** The driver can reject a bad message without using the value when nil is enough.

### Fixed
* Y10K and other out-of-range datetimes no longer fail decode.
* Unusual or invalid regex patterns can round-trip.
* `BSON.new(Bytes)` checks that the buffer has at least 5 bytes before it reads the size.
* Field names and regex patterns cannot contain a null byte when encoding.
* `Hash.from_bson` number conversion now uses the `V` type variable.
* Packed-bit encode now rejects ignored bits that are not zero.
* Removed the duplicate `Code` entry from `BSON::Value`.

## 0.7.0 - 2026-07-22

### Added
* **arch:** Added an explicit compile-time guard (`if flag?(:big_endian)`) to reject big-endian build targets safely at compile time.
* **object_id:** Added strict 24-character length validation in `BSON::ObjectId#initialize(str : String)`.

### Changed
* **object_id:** Switched process-wide random byte generation (`@@random_bytes`) to `Random::Secure` (CSPRNG) for cryptographic process uniqueness.
* **binary:** Split `BSON::Binary.from_vector` (`Int8` vs `Int32`) and `from_packed_bit_vector` (`UInt8` vs `Int32`) into distinct overloads to eliminate dead bounds checks and improve error messaging.
* **binary:** Added overflow validation for `Float64` vector inputs when converting to `Float32`.

### Performance
* **object_id:** Replaced heap string allocation in `ObjectId#to_s(io)` with a stack-allocated buffer (`UInt8[24]`) for zero-allocation IO formatting.
* **object_id:** Updated `ObjectId#to_canonical_extjson` to stream hex characters directly into `JSON::Builder`'s IO without intermediate string allocations.
* **object_id:** Replaced iterator-based `ObjectId.validate` with a single-pass ASCII byte range loop.
* **binary:** Replaced `IO::Memory` instantiation in `BSON::Binary.from_vector(Float32/Float64)` with direct `IO::ByteFormat::LittleEndian.encode` into pre-allocated payload slices.
* **builder:** Introduced pre-allocated static index strings (`STATIC_INDICES`) with `unsafe_fetch` for array indices `0..127` in `BSON::Builder`, eliminating heap string allocations during BSON array construction.
* **decoder:** Refactored `parse_regex_options` in `BSON::Decoder` to parse option flags directly from `Pointer(UInt8)` without intermediate `String` allocations.
* **decoder:** Optimized empty JSON object `{}` parsing to instantiate `BSON.new` directly, cutting intermediate heap allocations from 3 down to 1.
* **decoder:** Updated `Decimal128` field decoding to read from zero-copy pointer slices, eliminating temporary slice heap allocations and memory copies.
* **extjson:** Refactored `Regex#to_canonical_extjson` to stream option flags directly into the JSON builder's IO stream.

### Fixed
* **core:** Corrected byte-order initialization in `BSON.new(io : IO)` using explicit `IO::ByteFormat::LittleEndian.encode`.
* **decoder:** Widened `parse_regex_options` size parameter to `Int` to fix `LibC::SizeT` (`UInt64`) compiler type mismatch on 64-bit systems.

## 0.6.0 - 2026-07-14

### Added
* **spec:** Synced all remaining complex BSON corpus tests (`decimal128`, `dbref`, `code`, `regex`, etc.).
* **spec:** Added full support for the BSON corpus `parseErrors` test suite to guarantee ExtJSON parser compliance.
* **extjson:** Fully implemented Encrypted BSON (Subtype `0x06`) canonical ExtJSON representation via zero-allocation base64 streaming.

### Changed
* **decimal128:** Complete rewrite of `BSON::Decimal128` implementation to utilize native `UInt128` math, removing the heavy dependency on `require "big"` and `LibGMP`.
* **decimal128:** Removed cached instance variables from the struct, shrinking its memory footprint to exactly 16 bytes.
* **extjson:** Migrated `BSON::Decimal128`, `Int32`, `Int64`, `Float64`, `Slice`, `Time`, and `UUID` to stream their outputs directly to the `JSON::Builder`'s IO, eliminating intermediate string allocations.

### Fixed
* **extjson:** The JSON parser now strictly validates `$uuid` lengths (must be 36 characters).
* **extjson:** The JSON parser now rejects `null` bytes within document keys, mitigating potential injection vulnerabilities identified by the BSON corpus.
* **extjson:** Enforced strict type-checking for `$timestamp` (`t` and `i` must be integers).
* **core:** Pure BSON now properly treats invalid driver-level `DBRef` documents as standard `BSON::Document` fallbacks.

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
