<div align="center">
  <img src="icon.svg" width="128" height="128" />
  <h1>bson.cr</h1>
  <h3>A pure Crystal implementation of the <a href="http://bsonspec.org">BSON specification</a>.</h3>
  <a href="https://github.com/alumna/bson.cr/actions/workflows/crystal.yml"><img alt="Crystal CI" src="https://github.com/alumna/bson.cr/actions/workflows/crystal.yml/badge.svg"></a>
  <a href="https://github.com/alumna/bson.cr/tags"><img alt="GitHub tag (latest SemVer)" src="https://img.shields.io/github/v/tag/alumna/bson.cr"></a>
  <a href="https://github.com/alumna/bson.cr/blob/master/LICENSE"><img alt="GitHub" src="https://img.shields.io/github/license/alumna/bson.cr"></a>
</div>

This is a temporary fork to update the spec while also working on performance, stability, and modern MongoDB compatibility. Merging to upstream original repository is part of the plan, as soon as the work on updating `Cryomongo` is concluded.

It is expected to be faster, using less memory, and to strictly follow the newest MongoDB specification. Benchmarks will be added.

On a technical level, the current update already includes:

* **MongoDB 8.0 & Spec Compliance:** Full support for the most recent BSON specification, including the new Binary `Vector` types (Float32, Int8, PackedBit). Furthermore, it strictly passes all 1,025 tests in the official MongoDB BSON corpus, sealing vulnerabilities and ensuring perfect type preservation.
* **Zero-Allocation Core & ExtJSON:** Core workflows (including ObjectId handling, number decoding, and JSON streaming) process data directly in memory without creating temporary objects on the heap. Reduced GC pressure, increased throughput and higher peformance.
* **Native `Decimal128`:** The 128-bit decimal implementation was completely rewritten. The C-bindings (`LibGMP`/`BigInt`) were removed in favor of pure-Crystal `UInt128` bitwise operations, and the struct was reduced strictly to 16 bytes, as per the specification. It is now natively compiled and is deeply optimized.
* **Crystal 1.20 Ready:** Updated for the latest Crystal 1.20.x branch, replacing deprecated synchronization primitives (now using `Sync::Mutex`) and optimizing byte-level parsing logic.

### Roadmap & Checklist

The update roadmap is now concluded for this shard and the current work is now directed to update `Cryomongo`.

- [x] **BSON ObjectId** (`bson-objectid/objectid.md`): Currently up-to-date with the 12-byte modern specification.
- [x] **BSON Decimal128** (`bson-decimal128/decimal128.md`): Modern native `UInt128` implementation. Highly optimized and zero-allocation.
- [x] **BSON Binary UUID** (`bson-binary-uuid/uuid.md`): Subtypes `0x03` (Legacy) and `0x04` (UUID) are correctly declared and handled.
- [x] **BSON Binary Vector** (`bson-binary-vector/bson-binary-vector.md`): Subtype `0x09` is implemented for MongoDB's vector search capabilities (float32, int8, packed_bit).
- [x] **BSON Binary Encrypted** (`bson-binary-encrypted/binary-encrypted.md`): Subtype `0x06` is declared and strictly complies with the Extended JSON representation via zero-allocation Base64 streaming.
- [x] **BSON Corpus Sync (Part A)** (`bson-corpus/`): Ingested and passed the newest upstream corpus files for all standard types.
- [x] **BSON Corpus Sync (Part B)** (`bson-corpus/`): Ingested and passed all complex types (`decimal128`, `dbref`, etc.), including the strict `parseErrors` boundary test suite.
- [x] **Crystal 1.20 Modernization**: `shard.yml` now targets newer Crystal `1.20.x`, fix `Mutex` deprecations in favor of `Sync::Mutex` and update GitHub actions for Debian/Ubuntu 24.04 runners.

## Reliability

This library passes the official corpus tests located in the [`mongodb/specifications`](https://github.com/mongodb/specifications) repository.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     bson:
       github: elbywan/bson.cr
   ```

2. Run `shards install`

## API

[Full API documentation is hosted here.](https://elbywan.github.io/bson.cr/BSON.html)

## Usage

```crystal
require "bson"
```

### Constructors

```crystal
# Create a BSON instance from a NamedTuple…
bson = BSON.new({
  hello: "world"
})

# …or a Hash…
bson = BSON.new({
  "hello" => "world"
})

# …or a hex binary representation…
bytes = "160000000268656c6c6f0006000000776f726c640000".hexbytes
bson = BSON.new(bytes)

# …or an IO…
bson = BSON.new(IO::Memory.new bytes)

# …or JSON data
bson = BSON.from_json(%({
  "hello": "world"
}))

# The BSON binary representation is stored in the data property
puts bson.data.hexstring
# => 160000000268656c6c6f0006000000776f726c640000
```

### Append and fetch values

```crystal
bson = BSON.new({
  hello: "world"
})

# Append values
bson["name"] = BSON.new({
  first_name: "John",
  last_name: "Doe"
})

# Fetch values
puts bson["name"].as(BSON).to_json
# => {"first_name":"John","last_name":"Doe"}
puts bson["404"]?
# => nil

# Append another BSON
other_bson = BSON.new({ other: "field" })
bson.append(other_bson)
puts bson["other"]
# => field
```

### Vectors

```crystal
# You can encode arrays of Float32, Float64, Int8, or Int32 into BSON Binary Vectors (Subtype 0x09)
vector_binary = BSON::Binary.from_vector([1.5_f32, 2.0_f32, -3.2_f32])

bson = BSON.new
bson["embedding"] = vector_binary

# You can also encode packed bit arrays (UInt8 arrays representing boolean bits) with optional padding
packed_binary = BSON::Binary.from_packed_bit_vector([255_u8, 127_u8], padding: 3)

# To retrieve the vector data, use `#to_vector` and the respective extractor for zero-allocation Slice(T) views
binary = bson["embedding"].as(BSON::Binary)
if binary.subtype.vector?
  vector = binary.to_vector
  if vector.dtype.float32?
    slice = vector.as_float32
    puts slice[0] # => 1.5
  end
end
```

### Iterate

```crystal
bson = BSON.new({
  one: 1,
  two: 2.0,
  three: 3
})

# Enumerator
bson.each { |(key, value)|
  puts "#{key}, #{value}"
  # => one, 1
  # => two, 2.0
  # => three, 3
}

# Iterator
puts bson.each.map { |(key, value)|
  value.as(Number) + 1
}.to_a
# => [2, 3.0, 4]
```

### Conversions

```crystal
bson = BSON.new({
  one: 1,
  two: "2",
  binary: Slice[0_u8, 1_u8, 2_u8]
})

pp bson.to_h
# => {"one" => 1, "two" => "2", "binary" => Bytes[0, 1, 2]}

pp bson.each.to_a
# => [{"one", 1, Int32, nil}, {"two", "2", String, nil}, {"binary", Bytes[0, 1, 2], Binary, Generic}]
```

### JSON

```crystal
# Initialize from data in Relaxed Extended Json format.
# See: https://github.com/mongodb/specifications/blob/master/source/extended-json.rst
bson = BSON.new(%({
  "_id": {
       "$oid": "57e193d7a9cc81b4027498b5"
   },
   "Binary": {
       "$binary": {
           "base64": "o0w498Or7cijeBSpkquNtg==",
           "subType": "03"
       }
   },
   string: "String",
   number: 10.1
}))

# Serialize to Relaxed Extended Json format…
puts bson.to_json
# => {"_id":{"$oid":"57e193d7a9cc81b4027498b5"},"Binary":{"$binary":{"base64":"o0w498Or7cijeBSpkquNtg==","subType":"03"}},"string":"String","number":10.1}

# …or Canonical Extended Json.
puts bson.to_canonical_extjson
# => {"_id":{"$oid":"57e193d7a9cc81b4027498b5"},"Binary":{"$binary":{"base64":"o0w498Or7cijeBSpkquNtg==","subType":"03"}},"string":"String","number":{"$numberDouble":"10.1"}}
```

## Serialization

```crystal
class Data
  include BSON::Serializable
  include JSON::Serializable

  property field : String
  property counter : Int32

  property nested : Nested

  class Nested
    include BSON::Serializable
    include JSON::Serializable

    property array : Array(String | Int32)
  end
end

data = Data.from_json(%({
  "field": "value",
  "counter": 0,
  "nested": {
    "array": [
      "element",
      1
    ]
  }
}))

puts data.to_json
# => {"field":"value","counter":0,"nested":{"array":["element",1]}}

puts data.to_bson.data.hexstring
# => 52000000026669656c64000600000076616c75650010636f756e7465720000000000036e65737465640027000000046172726179001b00000002300008000000656c656d656e740010310001000000000000

puts Data.from_bson(data.to_bson).to_json
# => {"field":"value","counter":0,"nested":{"array":["element",1]}}
```

## Validating and creating ObjectIds

ObjectIds are constructed securely using `Random::Secure` (CSPRNG) for process uniqueness. You can validate that a provided string is a valid 24-character hex ObjectId before instantiating it:

```crystal
# => true
p BSON::ObjectId.validate("57e193d7a9cc81b4027498b5")

# => false
p BSON::ObjectId.validate("qwerty")

# => false (must be exactly 24 characters)
p BSON::ObjectId.validate("1234567890abcdefghijklmn123456")

# Bonus: formatting to an IO is completely zero-allocation via a stack buffer
io = IO::Memory.new
oid = BSON::ObjectId.new
oid.to_s(io)
```

## Decimal128

The `BSON::Decimal128` type is implemented natively in Crystal. It uses `UInt128` bitwise operations to accurately conform to the 34-digit precision IEEE-754 decimal128 standard. It does not rely on `LibGMP` (BigInt) bindings and is fully optimized for zero-allocation Extended JSON streaming, making it really fast.

## Contributing

1. Fork it (<https://github.com/elbywan/bson/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [elbywan](https://github.com/elbywan) - creator and maintainer
- [paulocoghi](https://github.com/paulocoghi) - contributor
