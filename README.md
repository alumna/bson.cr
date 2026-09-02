<div align="center">
  <img src="icon.svg" width="128" height="128" />
  <h1>bson.cr</h1>
  <h3>A pure Crystal implementation of the <a href="http://bsonspec.org">BSON specification</a>.</h3>
  <a href="https://github.com/alumna/bson.cr/actions/workflows/crystal.yml"><img alt="Crystal CI" src="https://github.com/alumna/bson.cr/actions/workflows/crystal.yml/badge.svg"></a>
  <a href="https://github.com/alumna/bson.cr/tags"><img alt="GitHub tag (latest SemVer)" src="https://img.shields.io/github/v/tag/alumna/bson.cr"></a>
  <a href="https://github.com/alumna/bson.cr/blob/master/LICENSE"><img alt="GitHub" src="https://img.shields.io/github/license/alumna/bson.cr"></a>
</div>

This is a temporary fork to update the spec, raise performance, and prepare the `Cryomongo` driver for MongoDB 8.0. A merge back to the original repository is planned when that driver work is done.

The library is a pure Crystal BSON codec. It follows the official MongoDB BSON and Extended JSON specs. It uses less heap memory on the common paths (views, inline ObjectId, one-pass builders).

### What this version includes

* **MongoDB 8.0 BSON:** All current types, including Binary Vector (`0x09`: Float32, Int8, PackedBit) and Encrypted (`0x06`) ExtJSON.
* **Full range DateTime and Regex:** `BSON::DateTime` stores `int64` milliseconds (including Y10K). `BSON::Regex` stores pattern and options as text and does not compile PCRE on decode.
* **Cryomongo helpers:** `BSON.build`, public `BSON::Builder`, `BSON.parse` / `parse?`, `from_json?`, `from_io?`, and `BSON.view` for zero-copy nested documents.
* **`to_h`:** Nested documents and arrays decode into `Hash` / `Array` in one pass (no child `BSON.view`). `each` still yields nested views.
* **Native Decimal128:** 16-byte `UInt128` math. No LibGMP in the default require. `BigDecimal` is optional.
* **Crystal 1.20 / 1.21:** ObjectId uses `Atomic`. After `fork` on Unix the process-unique bytes are rebuilt. Regex `m` and `s` flags follow Crystal 1.21.

The official MongoDB BSON corpus and extra prose tests pass.

## Installation

Add this to your `shard.yml`:

```yaml
dependencies:
  bson:
    github: alumna/bson.cr
```

Then run `shards install`.

Crystal `>= 1.20.0` is required.

## API

[Full API documentation is hosted here.](https://elbywan.github.io/bson.cr/BSON.html)

## Usage

```crystal
require "bson"
```

### Build a document

Prefer `BSON.build` when you write many fields. It uses one buffer. Avoid many `[]=` calls in a loop; each `[]=` rebuilds the document.

```crystal
# One pass (best for Cryomongo)
bson = BSON.build do |b|
  b["_id"] = BSON::ObjectId.new
  b["ok"] = 1.0
  b["name"] = "Ada"
end

# Nested document / array in the same buffer (no child BSON)
bson = BSON.build do |b|
  b.document("user") do
    b["name"] = "Ada"
    b["age"] = 30_i64
  end
  b.array("tags") do
    b["0"] = "math"
    b["1"] = "code"
  end
end

# NamedTuple or Hash
bson = BSON.new({hello: "world"})
bson = BSON.new({"hello" => "world"})

# Bytes (copied) or IO
bytes = "160000000268656c6c6f0006000000776f726c640000".hexbytes
bson = BSON.new(bytes)
bson = BSON.new(IO::Memory.new(bytes))

# Zero-copy view over a buffer you already own
view = BSON.view(bytes)
```

### Parse without raise

`BSON::Error` is raised for bad BSON or bad ExtJSON. Use the `?` methods when your implementaiton (or Cryomongo) should treat bad input as `nil`.

```crystal
BSON.parse(bytes)                 # raises BSON::Error if invalid
BSON.parse?(bytes)                # BSON | Nil
BSON.from_json(json)              # raises on bad ExtJSON
BSON.from_json?(json)             # BSON | Nil
BSON.from_io?(io)                 # BSON | Nil
```

### Append and fetch

```crystal
bson = BSON.new({hello: "world"})
bson["name"] = BSON.new({first_name: "John", last_name: "Doe"})
puts bson["name"].as(BSON).to_json
puts bson["404"]? # => nil

other = BSON.new({other: "field"})
bson.append(other)
```

To append many fields to an existing document, use the block form:

```crystal
bson.append do |b|
  b["a"] = 1
  b["b"] = 2
end
```

### DateTime

Decode always returns `BSON::DateTime`. It holds the full BSON `int64` millisecond range. Convert to Crystal `Time` when you need it.

```crystal
dt = bson["created_at"].as(BSON::DateTime)
dt.milliseconds          # Int64
dt.to_time               # Time (raises if outside Crystal range)
dt.to_time?              # Time | Nil
dt.relaxed?              # true for years 1970..9999

# Encode accepts Time or BSON::DateTime
bson["ts"] = Time.utc
bson["far"] = BSON::DateTime.new(253_402_300_800_000_i64) # Y10K
```

`BSON::Serializable` fields of type `Time` still work. The library converts `BSON::DateTime` to `Time`.
A field of type `BSON::Value` keeps `BSON::DateTime`. `Array` and `Hash` of `BSON::Value` do the same.

### Regex

Decode always returns `BSON::Regex`. The pattern is not compiled. This keeps unusual or invalid patterns and avoids PCRE cost on decode.

```crystal
rx = bson["filter"].as(BSON::Regex)
rx.pattern    # String
rx.options    # alphabetical letters, for example "imx"
rx.to_regex   # Crystal Regex (raises if the pattern is not valid PCRE)
rx.to_regex?  # Crystal Regex | Nil

# Encode accepts BSON::Regex or Crystal Regex
bson["re"] = BSON::Regex.new("foo*", "ix")
bson["re"] = /foo*/ix
```

`BSON::Serializable` fields of type `Regex` still work. The library calls `#to_regex`.
A field of type `BSON::Value` keeps `BSON::Regex`. `Array` and `Hash` of `BSON::Value` do the same.

### Vectors

```crystal
vector_binary = BSON::Binary.from_vector([1.5_f32, 2.0_f32, -3.2_f32])
bson = BSON.new
bson["embedding"] = vector_binary

packed_binary = BSON::Binary.from_packed_bit_vector([255_u8, 127_u8], padding: 3)

binary = bson["embedding"].as(BSON::Binary)
if binary.subtype.vector?
  vector = binary.to_vector
  if vector.dtype.float32?
    slice = vector.as_float32
    puts slice[0] # => 1.5
  end
end
```

UUID helpers: `BSON::Binary.new(uuid)`, `BSON::Binary.new(uuid, :java_legacy)`, and `#as_uuid`.

### Iterate

```crystal
bson.each { |(key, value)|
  puts "#{key}, #{value}"
}
```

### JSON

```crystal
bson = BSON.from_json(%({
  "_id": {"$oid": "57e193d7a9cc81b4027498b5"},
  "string": "String",
  "number": 10.1
}))

puts bson.to_json
puts bson.to_canonical_extjson
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
  "nested": {"array": ["element", 1]}
}))

puts Data.from_bson(data.to_bson).to_json
```

`to_bson` writes all fields in one builder pass.

## ObjectId

ObjectIds use `Random::Secure` for the 5 process-unique bytes and an `Atomic` counter. After `fork` on Unix those bytes are rebuilt so the child process does not reuse the parent prefix.

```crystal
BSON::ObjectId.validate("57e193d7a9cc81b4027498b5") # => true

oid = BSON::ObjectId.new
oid.timestamp          # UInt32, unsigned Unix seconds
oid.generation_time    # Time
oid.to_s(io)           # writes 24 hex chars with no heap string
```

## Decimal128

`BSON::Decimal128` is native Crystal `UInt128` math (34 digits). The default `require "bson"` does not load LibGMP.

If you need `BigDecimal`:

```crystal
require "bson"
require "bson/optional/big_decimal"

decimal = BSON::Decimal128.new(BigDecimal.new("1234.5"))
decimal.to_big_d
```

## Notes for Cryomongo

* Build replies and commands with `BSON.build` or `BSON::Builder`. Do not use `[]=` in a loop.
* Nested documents from `each` are views (`BSON.view`). Keep the parent document alive while you use them.
* `to_h` copies nested documents and arrays into `Hash` / `Array`. Those values do not depend on the parent buffer.
* Treat `BSON::Error` as a bad message. Use `parse?` / `from_json?` when a nil result is enough.
* Dates are `BSON::DateTime`. Call `#to_time` at the model edge if the app wants `Time`.
* Regex values are `BSON::Regex`. Compile with `#to_regex` only when you match text.

## Contributing

1. Fork it (<https://github.com/alumna/bson.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [elbywan](https://github.com/elbywan) - creator and maintainer
- [paulocoghi](https://github.com/paulocoghi) - contributor
