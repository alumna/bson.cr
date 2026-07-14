## bson.cr - temporary fork

This is a temporary fork of [github.com/elbywan/bson.cr](https://github.com/elbywan/bson.cr) in which the objective is to gradually update it to the more recent BSON specification, focusing one being compatible with MongoDB 8.0. It also aims to modernize the codebase with Crystal 1.20.x, like updating it to the new `Sync::Mutex`, among other things.

The fork is to allow a work without concerns on retro-compatibility in the short term and to, eventually, help paving the way for a future merge at the upstream repository, with the retro-compatibility challenges tackled at a later stage.

This is an ongoing effort to also update [cryomongo](github.com/elbywan/cryomongo), temporarily forked at [github.com/alumna/cryomongo](https://github.com/alumna/cryomongo), with the objective of being available for a future upstream merge in the original repository, if and when desired by the main maintainers.

If you don't need compatibility with recent MongoDB, then the upstream repositories mentioned above are the correct choice. The objective here is not to replace them. But to try in a safe fork to gradually update things until we achieved full compatibility, then as most retro-compatibility as possible. Then upstream merge.

### Roadmap & Checklist

Progress on the specifications to be implemented or updated:

- [x] **BSON ObjectId** (`bson-objectid/objectid.md`): Currently up-to-date with the 12-byte modern specification.
- [x] **BSON Decimal128** (`bson-decimal128/decimal128.md`): Basic spec implemented and passing existing corpus tests.
- [x] **BSON Binary UUID** (`bson-binary-uuid/uuid.md`): Subtypes `0x03` (Legacy) and `0x04` (UUID) are correctly declared and handled.
- [x] **BSON Binary Vector** (`bson-binary-vector/bson-binary-vector.md`): Subtype `0x09` is implemented for MongoDB's vector search capabilities (float32, int8, packed_bit).
- [ ] **BSON Binary Encrypted** (`bson-binary-encrypted/binary-encrypted.md`): Subtype `0x06` is declared in the enum, but we need to ensure full spec compliance (especially regarding Extended JSON representation).
- [x] **BSON Corpus Sync (Part A)** (`bson-corpus/`): Ingested and passed the newest upstream corpus files for all standard types. ExtJSON parsing and encoding logic stabilized.
- [x] **BSON Corpus Sync (Part B)** (`bson-corpus/`): Complex types (`decimal128`, `dbref`, etc.) are new synchronized and validated, including edge cases.
- [x] **Crystal 1.20 Modernization**: Ensure the `shard.yml` targets newer Crystal versions, fix `Mutex` deprecations, run `crystal tool format`, and update GitHub actions for Debian/Ubuntu 24.04 runners.

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

## Validating ObjectIds

You can validate that a provided string is a valid MongoDB ObjectId before instantiating it with `.new()` with:

```crystal
# => true
p BSON::ObjectId.validate("57e193d7a9cc81b4027498b5")

# => false
p BSON::ObjectId.validate("qwerty")

# => false
p BSON::ObjectId.validate("1234567890abcdefghijklmn")
```

## Decimal128

The `Decimal128` code has been hastily copied from the [`bson-ruby`](https://github.com/mongodb/bson-ruby/blob/master/lib/bson/decimal128.rb) library.
It works, but performance is low because it uses an intermediate String representation.

## Contributing

1. Fork it (<https://github.com/elbywan/bson/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [elbywan](https://github.com/elbywan) - creator and maintainer
- [paulocoghi](https://github.com/paulocoghi) - contributor
